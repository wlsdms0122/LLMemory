//
//  OperationsEngine.swift
//  LLMemory
//
//  Created by JSilver on 8/7/26.
//

import Foundation
import GRDB

public struct OperationsEngine: Sendable {
    // MARK: - Property
    // Assembled with the engine — handlers needing a collaborator captured
    // it at wiring time, so the registry is per-engine, not process-global.
    let registry: HandlerRegistry
    
    private let bodyProjection = BodyProjection()
    
    
    private let sectionEdit = SectionEdit()
    
    private let frontmatter = Frontmatter()
    
    private let noteFile = NoteFile()
    
    private let template = Template()

    private let frames = TemplateFrames()
    
    let keywords: any KeywordExtracting
    // The enrichment keys and defaults have one owner; this resolves them
    // from this brain each time they are needed.
    var enrichment: EnrichmentTuning { EnrichmentTuning(brain.config) }

    let brain: BrainContext

    // MARK: - Initializer
    init(lint: any LintScanning, keywords: any KeywordExtracting, brain: BrainContext) {
        self.registry = HandlerRegistry(lint: lint)
        self.keywords = keywords
        self.brain = brain
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
        _ db: Database,
        _ payload: [String: Any],
        sessionId: SessionId? = nil
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
                db,
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
        
        return result
    }
    
    // The gated apply sequence — validate, snapshot, savepointed op run,
    // post-checks, and the capture event that records the outcome.
    private func applySequence(
        _ db: Database,
        opsRaw: [[String: Any]],
        sessionId: SessionId?,
        rationale: String
    ) throws -> OperationsResult {
        let now = Int(Date().timeIntervalSince1970)
        let applyContext = HandlerContext(sessionId: sessionId, now: now, brain: brain)
        
        if let (message, index) = try validate(
            opsRaw,
            db: db,
            sessionId: sessionId,
            now: now
        ) {
            try? db.run(RecordEventTransaction(
                kind: .capture,
                payload: EventPayload([
                    "tx_status": "rejected",
                    "error": .string(message),
                    "rejected_index": index.map { index in .integer(index) },
                    "op_count": .integer(opsRaw.count)
                ]),
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
        
        let affected = try affectedPaths(opsRaw, context: applyContext, db: db)
        let backups: [(URL, String?)]
        do {
            backups = try snapshotFiles(affected)
        } catch {
            let message = "snapshot failed: \(error)"
            
            try? db.run(RecordEventTransaction(
                kind: .capture,
                payload: EventPayload([
                    "tx_status": "rejected",
                    "error": .string(message),
                    "op_count": .integer(opsRaw.count)
                ]),
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
        let eagerBefore = (try? db.run(CountEagerNotesTransaction())) ?? 0
        
        do {
            try db.inSavepoint {
                for (index, op) in opsRaw.enumerated() {
                    do {
                        results.append(try dispatchApply(op, context: applyContext, db: db))
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
                    brain.layout,
                    affected: affected,
                    backups: backups
                ) {
                    failure = (nil, sectionError)
                    
                    return .rollback
                }
                
                if let templateError = checkTemplateFrames(affected: affected, db: db) {
                    failure = (nil, templateError)
                    
                    return .rollback
                }
                
                if let capError = checkEagerCap(db: db, before: eagerBefore) {
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
            var payload: [String: JSONValue?] = [
                "tx_status": "failed",
                "error": .string(message),
                "op_count": .integer(opsRaw.count),
                "recovery_failed": JSONValue(recovery)
            ]
            
            if let index { payload["failed_index"] = .integer(index) }
            
            try? db.run(RecordEventTransaction(
                kind: .capture,
                payload: EventPayload(payload),
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
        
        let opsSummary = results.map { result in
            JSONValue.object([
                "op": .string(result.op),
                "status": .string(result.status),
                "ids": JSONValue(result.ids)
            ])
        }
        
        try? db.run(RecordEventTransaction(
            kind: .capture,
            payload: EventPayload([
                "tx_status": "ok",
                "op_count": .integer(opsRaw.count),
                "ops": .array(opsSummary)
            ]),
            sessionId: sessionId
        ))
        
        var degradedPasses: [String] = []
        let touched = enrichmentTouchedNotes(opsRaw)
        
        if !touched.isEmpty {
            // Best-effort, but atomically so — a failed validation pass
            // rolls back whole. The pass name rides the result; the error
            // detail rides the trace event.
            if case .failure(let error)? =
                try? db.attempt({ try db.run(
                    ValidatePendingTermsTransaction(
                        noteIds: touched,
                        keywords: keywords,
                        roundtripTopK: enrichment.roundtripTopK,
                        idfDFCeiling: enrichment.idfDFCeiling
                    )
                ) }) {
                degradedPasses.append("term_validation")
                
                try? db.run(
                    RecordEventTransaction(
                        kind: .capture,
                        payload: EventPayload([
                            "tx_status": "degraded",
                            "pass": "term_validation",
                            "error": .string("\(error)")
                        ]),
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
    
    public func dryRun(_ db: Database, _ payload: [String: Any], sessionId: SessionId? = nil) -> OperationsDryRunResult {
        guard let opsRaw = payload["ops"] as? [[String: Any]], !opsRaw.isEmpty else {
            return OperationsDryRunResult(
                status: "rejected",
                opCount: nil,
                error: "ops must be non-empty list",
                rejectedIndex: nil
            )
        }
        
        do {
            let result: (String?, Int?)? = try validate(opsRaw, db: db, sessionId: sessionId)
            
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
        _ layout: BrainLayout,
        affected: [URL],
        backups: [(URL, String?)]
    ) -> String? {
        let trashLookup = TrashedNoteLookup(layout: layout)
        var violations: [String] = []
        
        for url in affected {
            if url.pathExtension != "md" { continue }
            
            let noteId = trashLookup.trashStemId(url)
            let body: String
            do {
                guard let read = try noteFile.readNoteIfPresent(at: url) else { continue }
                
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
            
            if let preText = preImage(url, layout, nid: noteId, backups: backups),
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
        db: Database,
        sessionId: SessionId? = nil,
        now: Int = Int(Date().timeIntervalSince1970)
    ) throws -> (String, Int?)? {
        var context = HandlerContext(sessionId: sessionId, now: now, brain: brain)
        
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
                db: db
            ) {
                return ("op[\(index)] \(name): \(message)", index)
            }
            
            if let message = handler.schema.missingRequiredField(in: op) {
                return ("op[\(index)] \(name): \(message)", index)
            }
            
            if let message = try handler.validate(op, context, db) {
                return ("op[\(index)] \(name): \(message)", index)
            }
            
            if let message = try bodyProjection.advance(
                op: op,
                name: name,
                handler: handler,
                context: &context,
                db: db
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
        db: Database
    ) throws -> String? {
        if name != "create_note", !context.lockedInFlightIds.isEmpty {
            for noteId in handler.schema.mentionedNoteIds(in: op)
            where context.lockedInFlightIds.contains(noteId) {
                return "note is locked (human-only) — edit the file directly, not via ops: \(noteId)"
            }
        }
        
        let urls = try handler.touches(op, context, db)
        
        for url in urls {
            guard let noteId = brain.layout.id(ofFile: url) else { continue }
            
            if try db.run(NoteLockedTransaction(nid: noteId)) {
                return "note is locked (human-only) — edit the file directly, not via ops: \(noteId)"
            }
        }
        
        return nil
    }
    
    private func affectedPaths(
        _ ops: [[String: Any]],
        context: HandlerContext,
        db: Database
    ) throws -> [URL] {
        var seen = Set<String>()
        var paths: [URL] = []
        
        for op in ops {
            guard let name = op["op"] as? String,
                let handler = registry[name]
            else {
                continue
            }
            
            for url in try handler.touches(op, context, db) {
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
                throw OperationError.snapshotUnreadable(path: path.path, reason: "\(error)")
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
        _ url: URL,
        _ layout: BrainLayout,
        nid: String,
        backups: [(URL, String?)]
    ) -> String? {
        for (candidate, text) in backups where candidate.path == url.path {
            if let text { return text }
        }
        
        let trashLookup = TrashedNoteLookup(layout: layout)

        for (candidate, text) in backups where trashLookup.trashStemId(candidate) == nid {
            if let text { return text }
        }
        
        return nil
    }
    
    private func checkTemplateFrames(affected: [URL], db: Database) -> String? {
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
            
            if let noteId = brain.layout.id(ofFile: path) { affectedIds.append(noteId) }
        }
        
        var violations: [String] = []
        
        if !affectedIds.isEmpty {
            do {
                let dependents = try db.run(
                    FetchTemplateDependentNoteIdsTransaction(templateIds: affectedIds)
                )
                
                for noteId in dependents { enqueue(brain.layout.file(forId: noteId)) }
            } catch {
                violations.append("template reverse-dependency lookup failed: \(error)")
            }
        }
        
        for path in toCheck {
            if path.path.contains("/.trash/") { continue }
            
            let doc: FrontmatterDocument
            let body: String
            do {
                guard let read = try noteFile.readNoteIfPresent(at: path) else { continue }
                
                (doc, body) = read
            } catch {
                let noteId = brain.layout.id(ofFile: path) ?? path.lastPathComponent
                violations.append("\(noteId): unreadable, template frame unverifiable: \(error)")
                continue
            }
            
            guard let templateId = doc.template, !templateId.isEmpty else { continue }
            
            let noteId = brain.layout.id(ofFile: path) ?? path.lastPathComponent
            
            guard let frame = (try? frames.frame(db, brain, templateId: templateId)) ?? nil else {
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
    
    private func checkEagerCap(db: Database, before: Int) -> String? {
        let cap = brain.config.getInt("eager.max_count", default: 20)
        let after = (try? db.run(CountEagerNotesTransaction())) ?? 0
        
        if after > cap && after > before {
            return "eager cap exceeded (\(after)/\(cap)) — use priority=lazy (eager is the per-session BOOT working set)"
        }
        
        return nil
    }
    
    private func dispatchApply(_ op: [String: Any], context: HandlerContext, db: Database) throws -> OperationOutcome {
        let name = op["op"] as! String
        let handler = registry[name]!
        let raw = try handler.write(op, context, db)
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
