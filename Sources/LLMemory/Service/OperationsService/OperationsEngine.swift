//
//  OperationsEngine.swift
//  LLMemory
//
//  Created by JSilver on 8/7/26.
//

import Foundation

public struct OperationsEngine: Sendable {
    // MARK: - Property
    // Assembled with the engine — handlers needing a collaborator captured
    // it at wiring time, so the registry is per-engine, not process-global.
    let registry: HandlerRegistry
    
    private let bodyProjection = BodyProjection()
    private let noteExistence = NoteExistence()
    
    private let trashLookup = TrashedNoteLookup()
    
    private let sectionEdit = SectionEdit()
    
    private let frontmatter = Frontmatter()
    
    private let noteFiles = Notes()
    
    private let template = Template()
    
    // MARK: - Initializer
    // The collaborators are parameters, not fields: they belong to the two
    // handlers that use them, and the engine is the wiring that hands them
    // over. A field here would say the engine uses them too, and would be the
    // second path to them.
    init(genome: any GenomeServiceable, lint: any LintScanning) {
        self.registry = HandlerRegistry(genome: genome, lint: lint)
    }
    
    // MARK: - Public
    // The one place the raw payload string re-enters the [String: Any] world —
    // both ops transactions decode through here.
    func decodePayload(_ json: String) -> [String: Any]? {
        guard
            let data = json.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data),
            let payload = object as? [String: Any]
        else { return nil }
        
        return payload
    }
    
    // Catalog reads — the schema vocabulary the registry carries.
    func operationNames() -> [String] {
        registry.names
    }
    
    func operationSchema(_ name: String) -> OperationSchema? {
        registry[name]?.schema
    }
    
    // Runs inside the caller's write scope — OperationsService provides the
    // cross-process write lock via `storage.run`.
    public func apply(
        _ scope: GRDBScope,
        _ payload: [String: Any],
        sessionId: String? = nil
    ) -> OperationsResult {
        let rationale = payload["rationale"] as? String ?? ""
        
        guard let opsRaw = payload["ops"] as? [[String: Any]], !opsRaw.isEmpty else {
            return OperationsResult(
                status: "rejected",
                opResults: [],
                error: "ops must be non-empty list",
                rejectedIndex: nil,
                rationale: rationale,
                recoveryFailed: []
            )
        }
        
        let result: OperationsResult
        
        do {
            result = try applySequence(
                scope,
                opsRaw: opsRaw,
                sessionId: sessionId,
                rationale: rationale
            )
        } catch let conflict as SplitConflict {
            result = OperationsResult(
                status: "conflict",
                opResults: [],
                error: "split_note '\(conflict.fromId)' has \(conflict.unresolved.count) artifact(s) whose ownership across the new notes is a semantic call — re-issue with `routing` assigning each to children (to:[\"id\"]), copying (to:[\"a\",\"b\"]), or dropping (to:[]). Omitted artifacts are dropped; cooccur/reference are auto-handled.",
                rejectedIndex: nil,
                rationale: rationale,
                recoveryFailed: [],
                conflict: conflict
            )
        } catch {
            result = OperationsResult(
                status: "failed",
                opResults: [],
                error: "\(error)",
                rejectedIndex: nil,
                rationale: rationale,
                recoveryFailed: []
            )
        }
        
        // A rolled-back savepoint (op failure, split conflict, or a thrown
        // sequence) may have primed the in-process gene cache. All genome
        // writes live inside the savepoint, so the state read here equals
        // committed state; the engine owns this repair at its single exit,
        // and every caller — the fixture included — gets it.
        if result.status != "ok" { rewarmGenes(scope) }
        
        return result
    }
    
    // The gated apply sequence — validate, snapshot, savepointed op run,
    // post-checks, and the capture event that records the outcome.
    private func applySequence(
        _ scope: GRDBScope,
        opsRaw: [[String: Any]],
        sessionId: String?,
        rationale: String
    ) throws -> OperationsResult {
        let now = Int(Date().timeIntervalSince1970)
        let applyContext = HandlerContext(sessionId: sessionId, now: now)
        
        if let (message, index) = try validate(
            opsRaw,
            scope: scope.readOnly,
            sessionId: sessionId,
            now: now
        ) {
            try? scope.run(RecordEventTransaction(
                                        kind: Events.kindCapture,
                payload: [
                    "tx_status": "rejected",
                    "error": message,
                    "rejected_index": index,
                    "op_count": opsRaw.count
                ],
                sessionId: sessionId
            ))
            
            return OperationsResult(
                status: "rejected",
                opResults: [],
                error: message,
                rejectedIndex: index,
                rationale: rationale,
                recoveryFailed: []
            )
        }
        
        let affected = try affectedPaths(opsRaw, scope: scope.readOnly)
        let backups: [(URL, String?)]
        do {
            backups = try snapshotFiles(affected)
        } catch {
            let message = "snapshot failed: \(error)"
            
            try? scope.run(RecordEventTransaction(
                                        kind: Events.kindCapture,
                payload: [
                    "tx_status": "rejected",
                    "error": message,
                    "op_count": opsRaw.count
                ],
                sessionId: sessionId
            ))
            
            return OperationsResult(
                status: "rejected",
                opResults: [],
                error: message,
                rejectedIndex: nil,
                rationale: rationale,
                recoveryFailed: []
            )
        }
        
        var results: [OperationOutcome] = []
        var failure: (Int?, String)? = nil
        var splitConflict: (Int, SplitConflict)? = nil
        let eagerBefore = (try? scope.run(CountEagerNotesTransaction())) ?? 0
        
        do {
            try scope.savepoint {
                for (index, op) in opsRaw.enumerated() {
                    do {
                        results.append(try dispatchApply(op, context: applyContext, scope: scope))
                    } catch let conflict as SplitConflict {
                        splitConflict = (index, conflict)
                        
                        return .rollback
                    } catch {
                        let opName = op["op"] as? String ?? "?"
                        failure = (index, "\(opName): \(error)")
                        
                        return .rollback
                    }
                }
                
                if let sectionError = checkSectionInvariants(
                    affected: affected,
                    backups: backups
                ) {
                    failure = (nil, sectionError)
                    
                    return .rollback
                }
                
                if let templateError = checkTemplateFrames(affected: affected, scope: scope.readOnly) {
                    failure = (nil, templateError)
                    
                    return .rollback
                }
                
                if let capError = checkEagerCap(scope: scope.readOnly, before: eagerBefore) {
                    failure = (nil, capError)
                    
                    return .rollback
                }
                
                return .commit
            }
        } catch {
            if failure == nil {
                failure = (nil, "savepoint failed: \(error)")
            }
        }
        
        if let (index, conflict) = splitConflict {
            let recovery = restoreFiles(backups)
            
            return OperationsResult(
                status: "conflict",
                opResults: [],
                error: "split_note '\(conflict.fromId)' has \(conflict.unresolved.count) artifact(s) whose ownership across the new notes is a semantic call — re-issue with `routing` assigning each to children (to:[\"id\"]), copying (to:[\"a\",\"b\"]), or dropping (to:[]). Omitted artifacts are dropped; cooccur/reference are auto-handled.",
                rejectedIndex: index,
                rationale: rationale,
                recoveryFailed: recovery,
                conflict: conflict
            )
        }
        
        if let (index, message) = failure {
            let recovery = restoreFiles(backups)
            var payload: [String: Any?] = [
                "tx_status": "failed",
                "error": message,
                "op_count": opsRaw.count,
                "recovery_failed": recovery
            ]
            
            if let index { payload["failed_index"] = index }
            
            try? scope.run(RecordEventTransaction(
                                        kind: Events.kindCapture,
                payload: payload,
                sessionId: sessionId
            ))
            
            return OperationsResult(
                status: "failed",
                opResults: results,
                error: message,
                rejectedIndex: index,
                rationale: rationale,
                recoveryFailed: recovery
            )
        }
        
        let opsSummary: [[String: Any]] = results.map { result in
            ["op": result.op, "status": result.status, "ids": result.ids]
        }
        
        try? scope.run(RecordEventTransaction(
                                kind: Events.kindCapture,
            payload: [
                "tx_status": "ok",
                "op_count": opsRaw.count,
                "ops": opsSummary
            ],
            sessionId: sessionId
        ))
        
        var degradedPasses: [String] = []
        let touched = enrichmentTouchedNotes(opsRaw)
        
        if !touched.isEmpty {
            // Best-effort, but atomically so — a failed validation pass
            // rolls back whole. The pass name rides the result; the error
            // detail rides the trace event.
            if case .failure(let error)? =
                try? scope.attempt({ try scope.run(ValidatePendingTermsTransaction(noteIds: touched)) }) {
                degradedPasses.append("term_validation")
                
                try? scope.run(
                    RecordEventTransaction(
                        kind: Events.kindCapture,
                        payload: [
                            "tx_status": "degraded",
                            "pass": "term_validation",
                            "error": "\(error)"
                        ],
                        sessionId: sessionId
                    )
                )
            }
        }
        
        return OperationsResult(
            status: "ok",
            opResults: results,
            error: "",
            rejectedIndex: nil,
            rationale: rationale,
            recoveryFailed: [],
            degradedPasses: degradedPasses
        )
}
    
    public func dryRun(_ scope: GRDBReadScope, _ payload: [String: Any], sessionId: String? = nil) -> OperationsDryRunResult {
        guard let opsRaw = payload["ops"] as? [[String: Any]], !opsRaw.isEmpty else {
            return OperationsDryRunResult(
                status: "rejected",
                opCount: nil,
                error: "ops must be non-empty list",
                rejectedIndex: nil
            )
        }
        
        do {
            let result: (String?, Int?)? = try validate(opsRaw, scope: scope, sessionId: sessionId)
            
            if let (message, index) = result {
                return OperationsDryRunResult(
                    status: "rejected",
                    opCount: nil,
                    error: message,
                    rejectedIndex: index
                )
            }
            
            return OperationsDryRunResult(
                status: "ok",
                opCount: opsRaw.count,
                error: nil,
                rejectedIndex: nil
            )
        } catch let conflict as SplitConflict {
            return OperationsDryRunResult(
                status: "conflict",
                opCount: nil,
                error: "split_note '\(conflict.fromId)' needs routing for \(conflict.unresolved.count) ambiguous artifact(s)",
                rejectedIndex: nil
            )
        } catch {
            return OperationsDryRunResult(
                status: "rejected",
                opCount: nil,
                error: "\(error)",
                rejectedIndex: nil
            )
        }
    }
    
    func checkSectionInvariants(
        affected: [URL],
        backups: [(URL, String?)]
    ) -> String? {
        var violations: [String] = []
        
        for path in affected {
            if path.pathExtension != "md" { continue }
            
            let noteId = trashLookup.trashStemId(path)
            let body: String
            do {
                guard let read = try noteFiles.readNoteIfPresent(at: path) else { continue }
                
                body = read.body
            } catch {
                violations.append(
                    "\(noteId): unreadable after apply, section invariant unverifiable: \(error)"
                )
                continue
            }
            
            let collisions = sectionEdit.findPathCollisions(body)
            
            if collisions.isEmpty { continue }
            
            var existingPaths = Set<String>()
            
            if let preText = preImage(path, nid: noteId, backups: backups),
                let (_, preBody) = try? frontmatter.parse(preText) {
                existingPaths = Set(
                    sectionEdit.findPathCollisions(preBody).map { collision in
                        collision.path.display()
                    }
                )
            }
            
            let introduced = collisions.filter { collision in
                !existingPaths.contains(collision.path.display())
            }
            
            if introduced.isEmpty { continue }
            
            let details = introduced
                .map { collision in collision.display() }
                .joined(separator: "; ")
            violations.append("\(noteId): section path collision: \(details)")
        }
        
        if !violations.isEmpty {
            return "section invariant violated — " + violations.joined(separator: " | ")
        }
        
        return nil
    }
    
    // MARK: - Private
    private func enrichmentTouchedNotes(_ ops: [[String: Any]]) -> [String] {
        var touched = Set<String>()
        
        for op in ops {
            switch op["op"] as? String {
            case "add_retrieval_terms":
                if let noteId = op["id"] as? String, !noteId.isEmpty { touched.insert(noteId) }
            
            case "split_note":
                for child in (op["into"] as? [[String: Any]]) ?? [] {
                    if let childId = child["id"] as? String, !childId.isEmpty {
                        touched.insert(childId)
                    }
                }
            
            default:
                break
            }
        }
        
        return Array(touched)
    }
    
    private func validate(
        _ ops: [[String: Any]],
        scope: GRDBReadScope,
        sessionId: String? = nil,
        now: Int = Int(Date().timeIntervalSince1970)
    ) throws -> (String, Int?)? {
        var context = HandlerContext(sessionId: sessionId, now: now)
        
        for (index, op) in ops.enumerated() {
            guard let name = op["op"] as? String,
                let handler = registry[name]
            else {
                return ("op[\(index)] unknown: \(op["op"] ?? "nil")", index)
            }
            
            if let message = try lockedGate(
                op: op,
                name: name,
                handler: handler,
                context: context,
                scope: scope
            ) {
                return ("op[\(index)] \(name): \(message)", index)
            }
            
            if let message = handler.schema.missingRequiredField(in: op) {
                return ("op[\(index)] \(name): \(message)", index)
            }
            
            if let message = try handler.validate(op, context, scope) {
                return ("op[\(index)] \(name): \(message)", index)
            }
            
            if let message = try bodyProjection.advance(
                op: op,
                name: name,
                handler: handler,
                context: &context,
                scope: scope
            ) {
                return ("op[\(index)] \(name): \(message)", index)
            }
            
            let effect = handler.effect(op)
            context.inFlightIds.formUnion(effect["creates"] ?? [])
            context.invalidatedIds.formUnion(effect["invalidates"] ?? [])
            context.removedIds.formUnion(effect["removes"] ?? [])
            
            if name == "create_note", (op["locked"] as? Bool) == true,
                let noteId = op["id"] as? String, !noteId.isEmpty {
                context.lockedInFlightIds.insert(noteId)
            }
        }
        
        return nil
    }
    
    private func lockedGate(
        op: [String: Any],
        name: String,
        handler: any OperationHandling,
        context: HandlerContext,
        scope: GRDBReadScope
    ) throws -> String? {
        if name != "create_note", !context.lockedInFlightIds.isEmpty {
            for noteId in handler.schema.mentionedNoteIds(in: op)
            where context.lockedInFlightIds.contains(noteId) {
                return "note is locked (human-only) — edit the file directly, not via ops: \(noteId)"
            }
        }
        
        let urls = try handler.touches(op, scope)
        
        for url in urls {
            guard let noteId = Paths.id(ofFile: url) else { continue }
            
            if try scope.run(NoteLockedTransaction(nid: noteId)) {
                return "note is locked (human-only) — edit the file directly, not via ops: \(noteId)"
            }
        }
        
        return nil
    }
    
    private func affectedPaths(_ ops: [[String: Any]], scope: GRDBReadScope) throws -> [URL] {
        var seen = Set<String>()
        var paths: [URL] = []
        
        for op in ops {
            guard let name = op["op"] as? String,
                let handler = registry[name]
            else {
                continue
            }
            
            for url in try handler.touches(op, scope) {
                if !seen.contains(url.path) {
                    seen.insert(url.path)
                    paths.append(url)
                }
            }
        }
        
        return paths
    }
    
    private func snapshotFiles(_ targets: [URL]) throws -> [(URL, String?)] {
        var snapshot: [(URL, String?)] = []
        
        for path in targets {
            if !FileManager.default.fileExists(atPath: path.path) {
                snapshot.append((path, nil))
                continue
            }
            
            do {
                let text = try String(contentsOf: path, encoding: .utf8)
                snapshot.append((path, text))
            } catch {
                throw NSError(domain: "Transaction", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "snapshot read failed: \(path.path): \(error)"
                ])
            }
        }
        
        return snapshot
    }
    
    private func restoreFiles(_ backups: [(URL, String?)]) -> [String] {
        var failed: [String] = []
        
        for (path, text) in backups {
            do {
                if let text {
                    try text.write(to: path, atomically: true, encoding: .utf8)
                } else {
                    if FileManager.default.fileExists(atPath: path.path) {
                        try FileManager.default.removeItem(at: path)
                    }
                }
            } catch {
                failed.append(path.path)
            }
        }
        
        return failed
    }
    
    private func preImage(
        _ path: URL,
        nid: String,
        backups: [(URL, String?)]
    ) -> String? {
        for (url, text) in backups where url.path == path.path {
            if let text { return text }
        }
        
        for (url, text) in backups where trashLookup.trashStemId(url) == nid {
            if let text { return text }
        }
        
        return nil
    }
    
    private func checkTemplateFrames(affected: [URL], scope: GRDBReadScope) -> String? {
        var toCheck: [URL] = []
        var seen = Set<String>()
        
        func enqueue(_ url: URL) {
            if seen.insert(url.path).inserted { toCheck.append(url) }
        }
        
        var affectedIds: [String] = []
        
        // The id is the whole address, so the file name alone is only its last
        // label — reading it that way made every nested template's reverse
        // lookup miss, and miss silently, because a gate that finds nothing
        // looks exactly like a gate that found nothing wrong.
        for path in affected where path.pathExtension == "md" {
            enqueue(path)
            
            if let noteId = Paths.id(ofFile: path) { affectedIds.append(noteId) }
        }
        
        var violations: [String] = []
        
        if !affectedIds.isEmpty {
            do {
                let dependents = try scope.run(
                    FetchTemplateDependentNoteIdsTransaction(templateIds: affectedIds)
                )
                
                for noteId in dependents { enqueue(Paths.file(forId: noteId)) }
            } catch {
                violations.append("template reverse-dependency lookup failed: \(error)")
            }
        }
        
        for path in toCheck {
            if path.path.contains("/.trash/") { continue }
            
            let doc: FrontmatterDoc
            let body: String
            do {
                guard let read = try noteFiles.readNoteIfPresent(at: path) else { continue }
                
                (doc, body) = read
            } catch {
                let noteId = Paths.id(ofFile: path) ?? path.lastPathComponent
                violations.append("\(noteId): unreadable, template frame unverifiable: \(error)")
                continue
            }
            
            guard let templateId = doc.template, !templateId.isEmpty else { continue }
            
            let noteId = Paths.id(ofFile: path) ?? path.lastPathComponent
            
            guard let frame = (try? scope.run(LoadTemplateFrameTransaction(templateId: templateId))) ?? nil else {
                violations.append("\(noteId): unknown template '\(templateId)'")
                continue
            }
            
            if let violation = template.validate(documentBody: body, frame: frame) {
                violations.append("\(noteId) [template \(templateId)]: \(violation)")
            }
        }
        
        if !violations.isEmpty {
            return "template frame violated — " + violations.joined(separator: " | ")
        }
        
        return nil
    }
    
    private func checkEagerCap(scope: GRDBReadScope, before: Int) -> String? {
        let cap = Config.getInt("eager.max_count", default: 20)
        let after = (try? scope.run(CountEagerNotesTransaction())) ?? 0
        
        if after > cap && after > before {
            return "eager cap exceeded (\(after)/\(cap)) — use priority=lazy (eager is the per-session BOOT working set)"
        }
        
        return nil
    }
    
    private func dispatchApply(_ op: [String: Any], context: HandlerContext, scope: GRDBScope) throws -> OperationOutcome {
        let name = op["op"] as! String
        let handler = registry[name]!
        let raw = try handler.write(op, context, scope)
        var paths: [String] = []
        
        if let rawPaths = raw["paths"] as? [Any] {
            paths = rawPaths.map { path in "\(path)" }
        }
        
        if let path = raw["path"] as? String, !path.isEmpty {
            paths.insert(path, at: 0)
        }
        
        let ids = (raw["ids"] as? [Any])?.compactMap { id in id as? String } ?? []
        
        return OperationOutcome(
            op: name,
            status: raw["status"] as? String ?? "ok",
            note: raw["note"] as? String ?? "",
            paths: paths,
            ids: ids
        )
    }
}

private extension OperationsEngine {
    // Repairs the in-process gene cache from (effectively) committed state.
    func rewarmGenes(_ scope: GRDBScope) {
        guard let values = try? scope.run(FetchGenomeValuesTransaction()) else { return }
        
        Genes.warm(values)
    }
}
