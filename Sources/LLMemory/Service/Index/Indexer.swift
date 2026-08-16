//
//  Indexer.swift
//  LLMemory
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import GRDB

// Index reconciliation mechanics — scanning cortex/, parsing notes and
// reconciling the projection into the database.
public struct Indexer: Sendable {
    public struct BuildResult: Sendable {
        // MARK: - Property
        public let count: Int
        public let changed: Int
        public let orphans: Int
        public let errors: [String]

        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }

    public enum IntegrityLevel: Int, CaseIterable, Sendable {
        case l0 = 0, l1 = 1, l2 = 2, l3 = 3, l4 = 4
    }

    public struct ValidateResult: Sendable {
        // MARK: - Property
        public let activated, rejected, stillPending, staleRejected: Int
        public let rejectBreakdown: [String: Int]

        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }

    public struct ReindexOutcome: Sendable {
        public enum Result: Sendable {
            case reindexed(noteId: String, relativePath: String)
            case failure(String)
        }

        // MARK: - Property
        public let filePath: String
        public let result: Result

        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }

    struct Scan: Sendable {
        // MARK: - Property
        let pending: [PendingNote]
        let scannedRels: Set<String>
        let errors: [String]

        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }

    struct PendingNote: Sendable {
        // MARK: - Property
        let file: URL
        let rel: String
        let raw: String
        let contentHash: String
        let fields: FrontmatterDocument
        let body: String

        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }

    // MARK: - Property
    private let frontmatter = Frontmatter()

    private let noteFile = NoteFile()

    // MARK: - Initializer
    // MARK: - Public
    // Caller holds the write lock (run's write marker or an explicit writeLock).
    // Scanning and parsing stay outside the transaction — only the reconcile
    // holds the lock.
    func buildLocked(
        _ queue: any DatabaseWriter,
        _ brain: BrainContext,
        rebuild: Bool = false
    ) throws -> BuildResult {
        let scanned = scanPending(brain)

        return try queue.write { db in
            try reconcile(
                brain,
                db,
                pending: scanned.pending,
                scannedRels: scanned.scannedRels,
                rebuild: rebuild,
                now: Int(Date().timeIntervalSince1970),
                fileErrors: scanned.errors
            )
        }
    }

    // The corpus scan — file I/O and parsing, no connection involved.
    func scanPending(_ brain: BrainContext) -> Scan {
        let files = brain.layout.scanNotes()
        var scannedRels = Set<String>()
        var pending: [PendingNote] = []
        var fileErrors: [String] = []

        for file in files {
            let relativePath: String
            do {
                relativePath = try brain.layout.requireRelative(of: file)
            } catch {
                fileErrors.append("\(file.path): \(error)")
                continue
            }

            if let rejection = brain.layout.addressRejection(of: file) {
                fileErrors.append("\(relativePath): \(rejection)")
                continue
            }

            scannedRels.insert(relativePath)

            do {
                let text = try String(contentsOf: file, encoding: .utf8)
                let (fields, body) = try frontmatter.parse(text)

                pending.append(
                    PendingNote(
                        file: file,
                        rel: relativePath,
                        raw: text,
                        contentHash: noteFile.contentHash(text),
                        fields: fields,
                        body: body
                    )
                )
            } catch {
                fileErrors.append("\(relativePath): \(error)")
            }
        }

        return Scan(pending: pending, scannedRels: scannedRels, errors: fileErrors)
    }

    func check(
        _ queue: any DatabaseReader,
        _ brain: BrainContext,
        level: IntegrityLevel = .l1
    ) throws -> (ok: Bool, msgs: [String]) {
        try check(queue, brain, rawLevel: level.rawValue)
    }

    // Applies each file as its own savepoint (one file = one rollback unit)
    // and reports outcomes as data — printing and exit codes are the CLI
    // surface's business, decided after the enclosing transaction commits.
    func reindexFiles(
        _ db: Database,
        _ brain: BrainContext,
        filePaths: [String]
    ) throws -> [ReindexOutcome] {
        var outcomes: [ReindexOutcome] = []

        for filePath in filePaths {
            var path = URL(fileURLWithPath: (filePath as NSString).expandingTildeInPath)

            if !path.path.hasPrefix("/") {
                path = brain.layout.brainRoot.appendingPathComponent(filePath)
            }

            path = path.standardizedFileURL.resolvingSymlinksInPath()

            if !FileManager.default.fileExists(atPath: path.path) {
                outcomes.append(ReindexOutcome(filePath: filePath, result: .failure("not found")))
                continue
            }

            if brain.layout.relative(of: path) == nil {
                outcomes.append(
                    ReindexOutcome(
                        filePath: filePath,
                        result: .failure("outside brain home \(brain.layout.brainRoot.path)")
                    )
                )
                continue
            }

            var failure: Error? = nil
            var reindexed: (noteId: String, relativePath: String)? = nil

            do {
                try db.inSavepoint {
                    do {
                        let noteId = try ReindexNoteFileTransaction(
                            noteId: try brain.requireNoteId(of: path),
                            path: path
                        )
                            .perform(db)

                        reindexed = (noteId, brain.layout.relative(of: path) ?? path.path)

                        return .commit
                    } catch {
                        failure = error

                        return .rollback
                    }
                }
            } catch {
                failure = failure ?? error
            }

            if let failure {
                outcomes.append(ReindexOutcome(filePath: filePath, result: .failure("\(failure)")))
            } else if let reindexed {
                outcomes.append(
                    ReindexOutcome(
                        filePath: filePath,
                        result: .reindexed(noteId: reindexed.noteId, relativePath: reindexed.relativePath)
                    )
                )
            }
        }

        return outcomes
    }

    // MARK: - Private
    func reconcile(
        _ brain: BrainContext,
        _ db: Database,
        pending: [PendingNote],
        scannedRels: Set<String>,
        rebuild: Bool,
        now: Int,
        fileErrors: [String] = []
    ) throws -> BuildResult {
        if rebuild {
            try SnapshotArtifactsForRebuildTransaction().perform(db)
            try db.execute(sql: "DELETE FROM notes")
            try db.execute(sql: "DELETE FROM tags")
            try db.execute(sql: "DELETE FROM notes_fts")
        }

        var seen = Set<String>()
        var errors = fileErrors
        var changed = 0
        let existingRows = try Row.fetchAll(db, sql: "SELECT id, content_hash FROM notes")
        var existingByPath: [String: (id: String, hash: String)] = [:]

        for row in existingRows {
            let id: String = row["id"]

            existingByPath[brain.layout.relativeFile(forId: id)] = (id, row["content_hash"])
        }

        // `seen` is claimed before the upsert on purpose: a file that fails to
        // project has still been observed, and orphan detection must not read
        // the absence of a successful projection as the absence of a file.
        //
        // No duplicate check: two files are two locations, and two locations are
        // two addresses. Nothing can claim an id that another file already has.
        func reconcileOne(_ note: PendingNote) throws {
            if let noteId = brain.layout.id(ofFile: note.file) { seen.insert(noteId) }

            if let previous = existingByPath[note.rel],
                previous.hash == note.contentHash && !rebuild {
                return
            }

            try UpsertNoteTransaction(
                noteId: try brain.requireNoteId(of: note.file),
                file: note.file,
                fields: note.fields,
                body: note.body,
                raw: note.raw,
                now: now
            )
                .perform(db)
            changed += 1
        }

        for note in pending {
            do {
                try reconcileOne(note)
            } catch {
                errors.append("\(note.rel): \(error)")
            }
        }

        let orphans: Set<String>
        if fileErrors.isEmpty {
            orphans = Set(
                existingByPath
                    .filter { entry in !scannedRels.contains(entry.key) }
                    .map { entry in entry.value.id }
            ).subtracting(seen)
        } else {
            orphans = []
        }

        for orphan in orphans {
            try DeleteNoteRowTransaction(nid: orphan).perform(db)
        }

        if rebuild {
            try RestoreArtifactsAfterRebuildTransaction().perform(db)
            try BumpCandidateGenerationTransaction().perform(db)
        }

        if rebuild && !errors.isEmpty {
            throw IndexError.rebuildAborted(errors)
        }

        let count = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM notes") ?? 0

        return BuildResult(
            count: count,
            changed: changed,
            orphans: orphans.count,
            errors: errors
        )
    }

    // MARK: - Private
    func check(
        _ queue: any DatabaseReader,
        _ brain: BrainContext,
        rawLevel level: Int
    ) throws -> (ok: Bool, msgs: [String]) {
        try queue.read { db in try check(db, brain, rawLevel: level) }
    }

    func check(
        _ db: Database,
        _ brain: BrainContext,
        rawLevel level: Int
    ) throws -> (ok: Bool, msgs: [String]) {
        let eagerCap = brain.config.getInt("eager.max_count", default: 20)
        var messages: [String] = []
        var ok = true
        let shape = try SchemaShape(migrations: Session.migrations).check(db)

        if !shape.isEmpty {
            messages.append(contentsOf: shape)
            ok = false
        }

        if level < 1 { return (ok, messages) }

        // Keyed by the id the file's own location spells. A file whose
        // frontmatter disagrees still lands here under its address, so the
        // disagreement surfaces as a mismatch rather than as two ghosts.
        var filesById: [String: URL] = [:]

        for file in brain.layout.scanNotes() {
            guard let id = brain.layout.id(ofFile: file) else {
                messages.append("L1\tunaddressable\t\(brain.layout.relative(of: file) ?? file.path)")
                ok = false
                continue
            }

            filesById[id] = file
        }

        struct DBRow {
            // MARK: - Property
            public let id: String
            let title: String
            public let summary: String?
            let priority: String
            let contentHash: String

            // MARK: - Initializer
            // MARK: - Public
            // MARK: - Private
        }

        var dbRows: [String: DBRow] = [:]
        var activeDBRows: [String: DBRow] = [:]
        let rows = try Row.fetchAll(db, sql: """
            SELECT id, title, summary, priority, content_hash
            FROM notes
            """)

        for row in rows {
            let id: String = row["id"]
            let record = DBRow(
                id: row["id"],
                title: row["title"],
                summary: row["summary"] as String?,
                priority: row["priority"],
                contentHash: row["content_hash"]
            )

            activeDBRows[id] = record
            dbRows[id] = record
        }

        for id in Set(filesById.keys).subtracting(activeDBRows.keys).sorted() {
            messages.append("L1\tmissing-in-db\t\(id)")
            ok = false
        }

        for id in Set(activeDBRows.keys).subtracting(filesById.keys).sorted() {
            messages.append("L1\torphan-in-db\t\(id)")
            ok = false
        }

        if level < 2 { return (ok, messages) }

        var dbTagsById: [String: Set<String>] = [:]
        let tagRows = try Row.fetchAll(db, sql: "SELECT note_id, tag FROM tags")

        for row in tagRows {
            let noteId: String = row["note_id"]
            dbTagsById[noteId, default: []].insert(row["tag"])
        }

        var dbExtraById: [String: [String: String]] = [:]

        for row in try Row.fetchAll(db, sql: "SELECT note_id, key, value FROM note_extra") {
            dbExtraById[row["note_id"] as String, default: [:]][row["key"] as String] = row["value"]
        }

        let ftsIds = Set(try String.fetchAll(db, sql: "SELECT DISTINCT id FROM notes_fts"))
        let noteIds = Set(dbRows.values.map { row in row.id })

        for (addressId, file) in filesById {
            let fields: FrontmatterDocument
            let text: String
            do {
                text = try String(contentsOf: file, encoding: .utf8)
                (fields, _) = try frontmatter.parse(text)
            } catch {
                messages.append("L2\tfrontmatter-parse\t\(addressId)\t\(error)")
                ok = false
                continue
            }

            guard let row = dbRows[addressId] else { continue }

            for (fieldName, dbValue) in [
                ("title", row.title),
                ("summary", row.summary ?? ""),
                ("priority", row.priority)
            ] {
                let fileValue: String
                switch fieldName {
                case "title":
                    fileValue = fields.title

                case "summary":
                    fileValue = fields.summary

                case "priority":
                    fileValue = fields.priority

                default:
                    fileValue = ""
                }

                if fileValue != dbValue
                    && !(fieldName == "priority" && fileValue.isEmpty && dbValue == "lazy") {
                    messages.append(
                        "L2\tfield-mismatch\t\(row.id)\t\(fieldName): file='\(fileValue)' db='\(dbValue)'"
                    )
                    ok = false
                }
            }

            let fileTags = Set(fields.tags)
            let dbTags = dbTagsById[row.id] ?? []

            if fileTags != dbTags {
                let onlyFile = fileTags.subtracting(dbTags).sorted()
                let onlyDB = dbTags.subtracting(fileTags).sorted()

                messages.append(
                    "L2\ttag-mismatch\t\(row.id)\tonly_in_file=\(onlyFile) only_in_db=\(onlyDB)"
                )
                ok = false
            }

            // note_extra is a projection like tags are, so it gets the same eye:
            // content_hash only proves the file has not moved since indexing, not
            // that the projection wrote what the file says.
            let dbExtra = dbExtraById[row.id] ?? [:]

            if fields.extra != dbExtra {
                let disagreeing = Set(fields.extra.keys).union(dbExtra.keys)
                    .filter { key in fields.extra[key] != dbExtra[key] }
                    .sorted()
                let detail = disagreeing.map { key in
                    "\(key): file=\(fields.extra[key].map { "'\($0)'" } ?? "-")"
                        + " db=\(dbExtra[key].map { "'\($0)'" } ?? "-")"
                }

                messages.append(
                    "L2\textra-mismatch\t\(row.id)\t\(detail.joined(separator: ", "))"
                )
                ok = false
            }

            if noteFile.contentHash(text) != row.contentHash {
                messages.append(
                    "L2\tstale-content\t\(row.id)\t(file text differs from indexed projection — reindex needed)"
                )
                ok = false
            }
        }

        for noteId in noteIds.subtracting(ftsIds).sorted() {
            messages.append("L2\tfts-missing\t\(noteId)")
            ok = false
        }

        for noteId in ftsIds.subtracting(noteIds).sorted() {
            messages.append("L2\tfts-orphan\t\(noteId)")
            ok = false
        }

        let headIds = Set(
            try String.fetchAll(db, sql: "SELECT id FROM notes_fts WHERE section = ''")
        )

        for noteId in ftsIds.subtracting(headIds).sorted() {
            messages.append("L2\tfts-headless\t\(noteId)\t(head row 없음 — index build --rebuild 필요)")
            ok = false
        }

        let linkRows = try Row.fetchAll(db, sql: "SELECT src, dst, kind FROM note_links")

        for row in linkRows {
            let src: String = row["src"]
            let dst: String = row["dst"]
            let kind: String = row["kind"]

            if !noteIds.contains(src) {
                messages.append("L2\tlink-src-missing\t\(src)->\(dst)/\(kind)")
                ok = false
            }

            if !noteIds.contains(dst) {
                messages.append("L2\tlink-dst-missing\t\(src)->\(dst)/\(kind)")
                ok = false
            }
        }

        if level < 3 { return (ok, messages) }

        let vocabSet = Set(try String.fetchAll(db, sql: "SELECT tag FROM tag_vocab"))

        for (_, row) in dbRows {
            let noteId = row.id
            let nsNoteId = noteId as NSString

            if NoteAddress.idRegex.firstMatch(
                in: noteId,
                range: NSRange(location: 0, length: nsNoteId.length)
            ) == nil {
                messages.append("L3\tinvalid-id\t\(noteId)\t(dot-joined kebab-case labels required)")
                ok = false
            }

            if !["eager", "lazy"].contains(row.priority) {
                messages.append("L3\tinvalid-priority\t\(noteId)\t\(row.priority)")
                ok = false
            }

            let tags = dbTagsById[noteId] ?? []

            for tag in tags.subtracting(vocabSet).sorted() {
                messages.append("L3\ttag-not-in-vocab\t\(noteId)\t\(tag)")
                ok = false
            }
        }

        let aliasRows = try Row.fetchAll(db, sql: "SELECT alias, canonical FROM tag_aliases")

        for row in aliasRows {
            let alias: String = row["alias"]
            let canonical: String = row["canonical"]

            if !vocabSet.contains(canonical) {
                messages.append("L3\talias-canonical-missing\t\(alias)\t-> \(canonical)")
                ok = false
            }
        }

        let linkKinds = try String.fetchAll(db, sql: "SELECT DISTINCT kind FROM note_links")

        for kind in linkKinds where LinkKind(rawValue: kind) == nil {
            messages.append("L3\tinvalid-link-kind\t\(kind)")
            ok = false
        }

        let eagerCount = try CountEagerNotesTransaction().perform(db)

        if eagerCount > eagerCap {
            messages.append("L3\teager-cap-exceeded\t\(eagerCount)/\(eagerCap)")
            ok = false
        }

        if level < 4 { return (ok, messages) }

        return (ok, messages)
    }
}
