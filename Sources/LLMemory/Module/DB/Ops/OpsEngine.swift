//
//  OpsEngine.swift
//  LLMemory
//
//  Created by JSilver on 8/7/26.
//

import Foundation
import GRDB

public enum OpsEngine {
    public struct OpResult: Encodable {
        // MARK: - Property
        public let op: String
        public let status: String
        public let note: String
        public let paths: [String]
        public let ids: [String]
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    public struct Result: Encodable {
        public enum CodingKeys: String, CodingKey {
            case status, rationale, conflict
            case opResults = "ops"
            case error
            case rejectedIndex = "rejected_index"
            case recoveryFailed = "recovery_failed"
        }
        
        // MARK: - Property
        public let status: String
        public let opResults: [OpResult]
        public let error: String
        public let rejectedIndex: Int?
        public let rationale: String
        public let recoveryFailed: [String]
        public let conflict: SplitConflict?
        
        // MARK: - Initializer
        public init(
            status: String,
            opResults: [OpResult],
            error: String,
            rejectedIndex: Int?,
            rationale: String,
            recoveryFailed: [String],
            conflict: SplitConflict? = nil
        ) {
            self.status = status
            self.opResults = opResults
            self.error = error
            self.rejectedIndex = rejectedIndex
            self.rationale = rationale
            self.recoveryFailed = recoveryFailed
            self.conflict = conflict
        }
        
        // MARK: - Public
        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            
            try container.encode(status, forKey: .status)
            try container.encode(rationale, forKey: .rationale)
            try container.encode(opResults, forKey: .opResults)
            
            if !error.isEmpty { try container.encode(error, forKey: .error) }
            
            if let rejectedIndex { try container.encode(rejectedIndex, forKey: .rejectedIndex) }
            
            if !recoveryFailed.isEmpty {
                try container.encode(recoveryFailed, forKey: .recoveryFailed)
            }
            
            if let conflict { try container.encode(conflict, forKey: .conflict) }
        }
        
        // MARK: - Private
    }
    
    public struct SplitConflict: Error, Encodable {
        public enum CodingKeys: String, CodingKey {
            case fromId = "from_id"
            case unresolved = "unresolved"
        }
        
        // MARK: - Property
        public let fromId: String
        public let unresolved: [NoteArtifacts.RouteArtifact]
        
        // MARK: - Initializer
        // MARK: - Public
        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            
            try container.encode(fromId, forKey: .fromId)
            try container.encode(unresolved, forKey: .unresolved)
        }
        
        // MARK: - Private
    }
    
    public struct DryRunResult: Encodable {
        public enum CodingKeys: String, CodingKey {
            case status
            case opCount = "op_count"
            case error
            case rejectedIndex = "rejected_index"
        }
        
        // MARK: - Property
        public let status: String
        public let opCount: Int?
        public let error: String?
        public let rejectedIndex: Int?
        
        // MARK: - Initializer
        // MARK: - Public
        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            
            try container.encode(status, forKey: .status)
            
            if let opCount { try container.encode(opCount, forKey: .opCount) }
            
            if let error { try container.encode(error, forKey: .error) }
            
            if let rejectedIndex { try container.encode(rejectedIndex, forKey: .rejectedIndex) }
        }
        
        // MARK: - Private
    }
    
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Public
    // The one place the raw payload string re-enters the [String: Any] world —
    // both ops transactions decode through here.
    static func decodePayload(_ json: String) -> [String: Any]? {
        guard
            let data = json.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data),
            let payload = object as? [String: Any]
        else { return nil }

        return payload
    }

    // Runs on a writer the caller already gated — ApplyOpsTransaction provides
    // the cross-process write lock via `storage.run`.
    public static func apply(
        _ queue: any DatabaseWriter,
        _ payload: [String: Any],
        sessionId: String? = nil,
        ruleset: String? = nil
    ) -> Result {
        let rationale = payload["rationale"] as? String ?? ""
        
        guard let opsRaw = payload["ops"] as? [[String: Any]], !opsRaw.isEmpty else {
            return Result(
                status: "rejected",
                opResults: [],
                error: "ops must be non-empty list",
                rejectedIndex: nil,
                rationale: rationale,
                recoveryFailed: []
            )
        }
        
        let effectiveRulesetId: String?
        do {
            effectiveRulesetId = try RulesetResolution.resolve(cliRuleset: ruleset)
        } catch let resolutionError as RulesetResolution.Error {
            return Result(
                status: "rejected",
                opResults: [],
                error: resolutionError.message,
                rejectedIndex: nil,
                rationale: rationale,
                recoveryFailed: []
            )
        } catch {
            return Result(
                status: "rejected",
                opResults: [],
                error: "\(error)",
                rejectedIndex: nil,
                rationale: rationale,
                recoveryFailed: []
            )
        }
        
        do {
            if let rulesetId = effectiveRulesetId {
                let exists = try queue.read { db in
                    try RulesetExistsTransaction(id: rulesetId).perform(db)
                }
                
                if !exists {
                    return Result(
                        status: "rejected",
                        opResults: [],
                        error: "unknown ruleset: \(rulesetId)",
                        rejectedIndex: nil,
                        rationale: rationale,
                        recoveryFailed: []
                    )
                }
            }
            
            let txResult: Result = try queue.write { db in
                if let (message, index) = try validate(
                    opsRaw,
                    db: db,
                    rulesetId: effectiveRulesetId
                ) {
                    Events.record(
                        db,
                        kind: Events.kindCapture,
                        payload: [
                            "tx_status": "rejected",
                            "error": message,
                            "rejected_index": index,
                            "op_count": opsRaw.count
                        ],
                        sessionId: sessionId
                    )
                    
                    return Result(
                        status: "rejected",
                        opResults: [],
                        error: message,
                        rejectedIndex: index,
                        rationale: rationale,
                        recoveryFailed: []
                    )
                }
                
                let affected = try affectedPaths(opsRaw, db: db)
                let backups: [(URL, String?)]
                do {
                    backups = try snapshotFiles(affected)
                } catch {
                    let message = "snapshot failed: \(error)"
                    
                    Events.record(
                        db,
                        kind: Events.kindCapture,
                        payload: [
                            "tx_status": "rejected",
                            "error": message,
                            "op_count": opsRaw.count
                        ],
                        sessionId: sessionId
                    )
                    
                    return Result(
                        status: "rejected",
                        opResults: [],
                        error: message,
                        rejectedIndex: nil,
                        rationale: rationale,
                        recoveryFailed: []
                    )
                }
                
                var results: [OpResult] = []
                var failure: (Int?, String)? = nil
                var splitConflict: (Int, SplitConflict)? = nil
                let eagerBefore = (try? Notes.eagerCount(db)) ?? 0
                
                do {
                    try db.inSavepoint {
                        for (index, op) in opsRaw.enumerated() {
                            do {
                                results.append(try dispatchApply(op, db: db))
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
                    
                    return Result(
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
                    
                    Events.record(
                        db,
                        kind: Events.kindCapture,
                        payload: payload,
                        sessionId: sessionId
                    )
                    
                    return Result(
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
                
                Events.record(
                    db,
                    kind: Events.kindCapture,
                    payload: [
                        "tx_status": "ok",
                        "op_count": opsRaw.count,
                        "ops": opsSummary
                    ],
                    sessionId: sessionId
                )
                
                return Result(
                    status: "ok",
                    opResults: results,
                    error: "",
                    rejectedIndex: nil,
                    rationale: rationale,
                    recoveryFailed: []
                )
            }
            
            if txResult.status != "ok" { rewarmGenome(queue) }
            
            if txResult.status == "ok" {
                let touched = enrichmentTouchedNotes(opsRaw)
                
                if !touched.isEmpty {
                    _ = try? queue.write { db in
                        try Validation.validatePendingTerms(db, noteIds: touched)
                    }
                }
            }
            
            return txResult
        } catch let conflict as SplitConflict {
            return Result(
                status: "conflict",
                opResults: [],
                error: "split_note '\(conflict.fromId)' has \(conflict.unresolved.count) artifact(s) whose ownership across the new notes is a semantic call — re-issue with `routing` assigning each to children (to:[\"id\"]), copying (to:[\"a\",\"b\"]), or dropping (to:[]). Omitted artifacts are dropped; cooccur/reference are auto-handled.",
                rejectedIndex: nil,
                rationale: rationale,
                recoveryFailed: [],
                conflict: conflict
            )
        } catch {
            rewarmGenome(queue)
            
            return Result(
                status: "failed",
                opResults: [],
                error: "\(error)",
                rejectedIndex: nil,
                rationale: rationale,
                recoveryFailed: []
            )
        }
    }
    
    public static func dryRun(_ queue: any DatabaseReader, _ payload: [String: Any], ruleset: String? = nil) -> DryRunResult {
        guard let opsRaw = payload["ops"] as? [[String: Any]], !opsRaw.isEmpty else {
            return DryRunResult(
                status: "rejected",
                opCount: nil,
                error: "ops must be non-empty list",
                rejectedIndex: nil
            )
        }
        
        let effectiveRulesetId: String?
        do {
            effectiveRulesetId = try RulesetResolution.resolve(cliRuleset: ruleset)
        } catch let resolutionError as RulesetResolution.Error {
            return DryRunResult(
                status: "rejected",
                opCount: nil,
                error: resolutionError.message,
                rejectedIndex: nil
            )
        } catch {
            return DryRunResult(
                status: "rejected",
                opCount: nil,
                error: "\(error)",
                rejectedIndex: nil
            )
        }
        
        do {
            if let rulesetId = effectiveRulesetId {
                let exists = try queue.read { db in try RulesetExistsTransaction(id: rulesetId).perform(db) }
                
                if !exists {
                    return DryRunResult(
                        status: "rejected",
                        opCount: nil,
                        error: "unknown ruleset: \(rulesetId)",
                        rejectedIndex: nil
                    )
                }
            }
            
            let result: (String?, Int?)? = try queue.read { db in
                try validate(opsRaw, db: db, rulesetId: effectiveRulesetId)
            }
            
            if let (message, index) = result {
                return DryRunResult(
                    status: "rejected",
                    opCount: nil,
                    error: message,
                    rejectedIndex: index
                )
            }
            
            return DryRunResult(
                status: "ok",
                opCount: opsRaw.count,
                error: nil,
                rejectedIndex: nil
            )
        } catch let conflict as SplitConflict {
            return DryRunResult(
                status: "conflict",
                opCount: nil,
                error: "split_note '\(conflict.fromId)' needs routing for \(conflict.unresolved.count) ambiguous artifact(s)",
                rejectedIndex: nil
            )
        } catch {
            return DryRunResult(
                status: "rejected",
                opCount: nil,
                error: "\(error)",
                rejectedIndex: nil
            )
        }
    }
    
    static func targetIds(_ op: [String: Any], schema: OpSchema) -> Set<String> {
        schema.mentionedNoteIds(in: op)
    }
    
    static func checkSectionInvariants(
        affected: [URL],
        backups: [(URL, String?)]
    ) -> String? {
        var violations: [String] = []
        
        for path in affected {
            if path.pathExtension != "md" { continue }
            
            let noteId = Handlers.trashStemId(path)
            let body: String
            do {
                guard let read = try Notes.readNoteIfPresent(at: path) else { continue }
                
                body = read.body
            } catch {
                violations.append(
                    "\(noteId): unreadable after apply, section invariant unverifiable: \(error)"
                )
                continue
            }
            
            let collisions = SectionEdit.findPathCollisions(body)
            
            if collisions.isEmpty { continue }
            
            var existingPaths = Set<String>()
            
            if let preText = preImage(path, nid: noteId, backups: backups),
                let (_, preBody) = try? Frontmatter.parse(preText) {
                existingPaths = Set(
                    SectionEdit.findPathCollisions(preBody).map { collision in
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
    private static func enrichmentTouchedNotes(_ ops: [[String: Any]]) -> [String] {
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
    
    private static func validate(
        _ ops: [[String: Any]],
        db: Database,
        rulesetId: String?
    ) throws -> (String, Int?)? {
        var context = HandlerContext()
        
        for (index, op) in ops.enumerated() {
            guard let name = op["op"] as? String,
                let handler = Handlers.registry[name]
            else {
                return ("op[\(index)] unknown: \(op["op"] ?? "nil")", index)
            }
            
            if let rulesetId,
                let message = try rulesetGate(
                    op: op,
                    name: name,
                    handler: handler,
                    db: db,
                    rulesetId: rulesetId
                ) {
                return ("op[\(index)] \(name): \(message)", index)
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
            
            if let message = Handlers.checkRequired(
                op,
                fields: handler.schema.requiredNames(given: op)
            ) {
                return ("op[\(index)] \(name): \(message)", index)
            }
            
            if let message = try handler.validate(op, context, db) {
                return ("op[\(index)] \(name): \(message)", index)
            }
            
            if let message = try BodyProjection.advance(
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

            if name == "create_note", let axis = op["axis"] as? String, !axis.isEmpty {
                context.inFlightAxes.insert(axis)
            }
        }
        
        return nil
    }
    
    private static func lockedGate(
        op: [String: Any],
        name: String,
        handler: OpHandler,
        context: HandlerContext,
        db: Database
    ) throws -> String? {
        if name != "create_note", !context.lockedInFlightIds.isEmpty {
            for noteId in targetIds(op, schema: handler.schema)
            where context.lockedInFlightIds.contains(noteId) {
                return "note is locked (human-only) — edit the file directly, not via ops: \(noteId)"
            }
        }
        
        let urls = try handler.touches(op, db)
        
        for url in urls {
            guard let relativePath = try? Notes.relativeToBrainRoot(url) else { continue }
            
            let locked = try Int.fetchOne(
                db,
                sql: "SELECT locked FROM notes WHERE path = ?",
                arguments: [relativePath]
            )
            
            if locked == 1 {
                return "note is locked (human-only) — edit the file directly, not via ops: \(relativePath)"
            }
        }
        
        return nil
    }
    
    private static func rulesetGate(
        op: [String: Any],
        name: String,
        handler: OpHandler,
        db: Database,
        rulesetId: String
    ) throws -> String? {
        var axes = try extractAxes(op, schema: handler.schema, db: db)
        
        if axes.isEmpty { axes = ["*"] }
        
        for axis in axes.sorted() {
            let effective = try RulesetService.effective(GRDBScope(db), axis: axis, rulesetIds: [rulesetId])
            let (allowed, reason) = effective.allows(op: name)
            
            if !allowed {
                return "blocked by ruleset '\(rulesetId)' for axis '\(axis)': \(reason ?? "denied")"
            }
        }
        
        return nil
    }
    
    private static func extractAxes(
        _ op: [String: Any],
        schema: OpSchema,
        db: Database
    ) throws -> Set<String> {
        var axes = schema.mentionedAxes(in: op)
        
        for noteId in schema.mentionedNoteIds(in: op) {
            if let axis = try axisOf(noteId, db: db) { axes.insert(axis) }
        }
        
        return axes
    }
    
    private static func axisOf(_ nid: String, db: Database) throws -> String? {
        try String.fetchOne(db, sql: "SELECT axis FROM notes WHERE id = ?", arguments: [nid])
    }
    
    private static func affectedPaths(_ ops: [[String: Any]], db: Database) throws -> [URL] {
        var seen = Set<String>()
        var paths: [URL] = []
        
        for op in ops {
            guard let name = op["op"] as? String,
                let handler = Handlers.registry[name]
            else {
                continue
            }
            
            for url in try handler.touches(op, db) {
                if !seen.contains(url.path) {
                    seen.insert(url.path)
                    paths.append(url)
                }
            }
        }
        
        return paths
    }
    
    private static func snapshotFiles(_ targets: [URL]) throws -> [(URL, String?)] {
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
    
    private static func restoreFiles(_ backups: [(URL, String?)]) -> [String] {
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
    
    private static func preImage(
        _ path: URL,
        nid: String,
        backups: [(URL, String?)]
    ) -> String? {
        for (url, text) in backups where url.path == path.path {
            if let text { return text }
        }
        
        for (url, text) in backups where Handlers.trashStemId(url) == nid {
            if let text { return text }
        }
        
        return nil
    }
    
    private static func checkTemplateFrames(affected: [URL], db: Database) -> String? {
        var toCheck: [URL] = []
        var seen = Set<String>()
        
        func enqueue(_ url: URL) {
            if seen.insert(url.path).inserted { toCheck.append(url) }
        }
        
        var affectedIds: [String] = []
        
        for path in affected where path.pathExtension == "md" {
            enqueue(path)
            affectedIds.append(path.deletingPathExtension().lastPathComponent)
        }
        
        var violations: [String] = []
        
        if !affectedIds.isEmpty {
            let placeholders = affectedIds.map { _ in "?" }.joined(separator: ",")
            
            do {
                let dependentPaths = try String.fetchAll(
                    db,
                    sql: "SELECT path FROM notes WHERE template IN (\(placeholders))",
                    arguments: StatementArguments(affectedIds)
                )
                
                for relativePath in dependentPaths {
                    enqueue(Paths.brainRoot.appendingPathComponent(relativePath))
                }
            } catch {
                violations.append("template reverse-dependency lookup failed: \(error)")
            }
        }
        
        for path in toCheck {
            if path.path.contains("/.trash/") { continue }
            
            let doc: FrontmatterDoc
            let body: String
            do {
                guard let read = try Notes.readNoteIfPresent(at: path) else { continue }
                
                (doc, body) = read
            } catch {
                let noteId = path.deletingPathExtension().lastPathComponent
                violations.append("\(noteId): unreadable, template frame unverifiable: \(error)")
                continue
            }
            
            guard let templateId = doc.template, !templateId.isEmpty else { continue }
            
            let noteId = doc.id.isEmpty
                ? path.deletingPathExtension().lastPathComponent
                : doc.id
            
            guard let frame = (try? Template.loadFrame(db, templateId: templateId)) ?? nil else {
                violations.append("\(noteId): unknown template '\(templateId)'")
                continue
            }
            
            if let violation = Template.validate(documentBody: body, frame: frame) {
                violations.append("\(noteId) [template \(templateId)]: \(violation)")
            }
        }
        
        if !violations.isEmpty {
            return "template frame violated — " + violations.joined(separator: " | ")
        }
        
        return nil
    }
    
    private static func checkEagerCap(db: Database, before: Int) -> String? {
        let cap = Config.getInt("eager.max_count", default: 20)
        let after = (try? Notes.eagerCount(db)) ?? 0
        
        if after > cap && after > before {
            return "eager cap exceeded (\(after)/\(cap)) — use priority=lazy (eager is the per-session BOOT working set)"
        }
        
        return nil
    }
    
    private static func dispatchApply(_ op: [String: Any], db: Database) throws -> OpResult {
        let name = op["op"] as! String
        let handler = Handlers.registry[name]!
        let raw = try handler.write(op, db)
        var paths: [String] = []
        
        if let rawPaths = raw["paths"] as? [Any] {
            paths = rawPaths.map { path in "\(path)" }
        }
        
        if let path = raw["path"] as? String, !path.isEmpty {
            paths.insert(path, at: 0)
        }
        
        let ids = (raw["ids"] as? [Any])?.compactMap { id in id as? String } ?? []
        
        return OpResult(
            op: name,
            status: raw["status"] as? String ?? "ok",
            note: raw["note"] as? String ?? "",
            paths: paths,
            ids: ids
        )
    }
}

private extension OpsEngine {
    // A rolled-back transaction may have primed the in-process gene cache —
    // reload it from the committed state, tolerating a dead connection.
    static func rewarmGenome(_ queue: any DatabaseReader) {
        guard let values = try? queue.read({ db in
            try FetchGenomeValuesTransaction().perform(db)
        }) else { return }

        Genome.warm(values)
    }
}
