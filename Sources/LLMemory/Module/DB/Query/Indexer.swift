//
//  Indexer.swift
//  LLMemory
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import GRDB

enum IndexError: Error, CustomStringConvertible {
    case duplicateId(String)
    case rebuildAborted([String])
    
    var description: String {
        switch self {
        case .duplicateId(let id):
            return "duplicate id \(id)"
        
        case .rebuildAborted(let errors):
            return "rebuild aborted — state would not survive the commit: \(errors.joined(separator: "; "))"
        }
    }
}

// Index reconciliation mechanics — scanning cortex/, parsing notes and
// reconciling the projection into the database.
public enum Indexer {
    public struct BuildResult {
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

    public struct ValidateResult {
        // MARK: - Property
        public let activated, rejected, stillPending, staleRejected: Int
        public let rejectBreakdown: [String: Int]
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }

    struct PendingNote {
        // MARK: - Property
        let file: URL
        let rel: String
        let raw: String
        let contentHash: String
        let fields: FrontmatterDoc
        let body: String
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }

    // MARK: - Property
    private static let idRegex = try! NSRegularExpression(pattern: #"^[a-z0-9][a-z0-9-]*$"#)

    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Public
    // Caller holds the write lock (run's write marker or an explicit writeLock).
    static func buildLocked(_ queue: any DatabaseWriter, rebuild: Bool = false) throws -> BuildResult {
        let now = Int(Date().timeIntervalSince1970)
        let files = Paths.scanNotes()
        var scannedRels = Set<String>()
        var pending: [PendingNote] = []
        var fileErrors: [String] = []
            
        func parseInto(_ list: inout [PendingNote], _ urls: [URL]) {
            for file in urls {
                let relativePath: String
                do {
                    relativePath = try Notes.relativeToBrainRoot(file)
                } catch {
                    fileErrors.append("\(file.path): \(error)")
                    continue
                }
                    
                scannedRels.insert(relativePath)
                    
                do {
                    let text = try String(contentsOf: file, encoding: .utf8)
                    let (fields, body) = try Frontmatter.parse(text)
                        
                    list.append(
                        PendingNote(
                            file: file,
                            rel: relativePath,
                            raw: text,
                            contentHash: Notes.contentHash(text),
                            fields: fields,
                            body: body
                        )
                    )
                } catch {
                    fileErrors.append("\(relativePath): \(error)")
                }
            }
        }
            
        parseInto(&pending, files)
            
        return try queue.write { db in
            try reconcile(
                db,
                pending: pending,
                scannedRels: scannedRels,
                rebuild: rebuild,
                now: now,
                fileErrors: fileErrors
            )
        }

    }

    // Caller holds the write lock (run's write marker or an explicit writeLock).
    @discardableResult
    static func reindexLocked(_ queue: any DatabaseWriter, filePaths: [String]) throws -> Int {
        var exitCode = 0

        for filePath in filePaths {
            var path = URL(fileURLWithPath: (filePath as NSString).expandingTildeInPath)

            if !path.path.hasPrefix("/") {
                path = Paths.brainRoot.appendingPathComponent(filePath)
            }

            path = path.standardizedFileURL.resolvingSymlinksInPath()

            if !FileManager.default.fileExists(atPath: path.path) {
                FileHandle.standardError.write(
                    "ERROR \(filePath): not found\n".data(using: .utf8)!
                )
                exitCode = 1
                continue
            }

            if Paths.relative(of: path) == nil {
                FileHandle.standardError.write(
                    "ERROR \(filePath): outside brain home \(Paths.brainRoot.path)\n"
                        .data(using: .utf8)!
                )
                exitCode = 1
                continue
            }

            do {
                let noteId = try queue.write { db in
                    try ReindexNoteFileTransaction(path: path).perform(db)
                }
                let relativePath = Paths.relative(of: path) ?? path.path

                print("reindexed: \(noteId) (\(relativePath))")
            } catch {
                FileHandle.standardError.write(
                    "ERROR \(filePath): \(error)\n".data(using: .utf8)!
                )
                exitCode = 1
            }
        }

        return exitCode

    }

    static func check(_ queue: any DatabaseReader, level: IntegrityLevel = .l1) throws -> (ok: Bool, msgs: [String]) {
        try check(queue, rawLevel: level.rawValue)
    }

    // MARK: - Private
    static func reconcile(
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
        let existingRows = try Row.fetchAll(db, sql: "SELECT path, id, content_hash FROM notes")
        var existingByPath: [String: (id: String, hash: String)] = [:]
        
        for row in existingRows {
            existingByPath[row["path"]] = (row["id"], row["content_hash"])
        }
        
        func reconcileOne(_ note: PendingNote) throws {
            if !note.fields.id.isEmpty {
                if seen.contains(note.fields.id) {
                    throw IndexError.duplicateId(note.fields.id)
                }
                
                seen.insert(note.fields.id)
            }
            
            if let previous = existingByPath[note.rel],
                previous.hash == note.contentHash && !rebuild {
                return
            }
            
            try UpsertNoteTransaction(file: note.file,
                fields: note.fields,
                body: note.body,
                raw: note.raw,
                now: now
            ).perform(db)
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
            try Dismissals.bumpGeneration(db)
        }
        
        if rebuild && !errors.isEmpty {
            throw IndexError.rebuildAborted(errors)
        }
        
        let count = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM notes") ?? 0
        
        for (key, value) in [("note_count", String(count)), ("last_build_at", String(now))] {
            try db.execute(sql: """
                INSERT INTO meta (key, value) VALUES (?, ?)
                ON CONFLICT(key) DO UPDATE SET value=excluded.value
                """, arguments: [key, value])
        }
        
        return BuildResult(
            count: count,
            changed: changed,
            orphans: orphans.count,
            errors: errors
        )
    }

    // MARK: - Private
    static func check(_ queue: any DatabaseReader, rawLevel level: Int) throws -> (ok: Bool, msgs: [String]) {
        let eagerCap = Config.getInt("eager.max_count", default: 20)
        
        return try queue.read { db in
            var messages: [String] = []
            var ok = true
            let shape = try SchemaShape(migrations: Session.migrations).check(db)
            
            if !shape.isEmpty {
                messages.append(contentsOf: shape)
                ok = false
            }
            
            if level < 1 { return (ok, messages) }
            
            var filesByRel: [String: URL] = [:]
            
            for file in Paths.scanNotes() {
                let relativePath = Paths.relative(of: file) ?? file.path
                filesByRel[relativePath] = file
            }
            
            struct DBRow {
                // MARK: - Property
                public let id: String
                let axis: String
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
                SELECT path, id, axis, title, summary, priority, content_hash
                FROM notes
                """)
            
            for row in rows {
                let path: String = row["path"]
                let record = DBRow(
                    id: row["id"],
                    axis: row["axis"],
                    title: row["title"],
                    summary: row["summary"] as String?,
                    priority: row["priority"],
                    contentHash: row["content_hash"]
                )
                
                activeDBRows[path] = record
                dbRows[path] = record
            }
            
            for path in Set(filesByRel.keys).subtracting(activeDBRows.keys).sorted() {
                messages.append("L1\tmissing-in-db\t\(path)")
                ok = false
            }
            
            for path in Set(activeDBRows.keys).subtracting(filesByRel.keys).sorted() {
                messages.append("L1\torphan-in-db\t\(path)\t\(activeDBRows[path]!.id)")
                ok = false
            }
            
            if level < 2 { return (ok, messages) }
            
            var dbTagsById: [String: Set<String>] = [:]
            let tagRows = try Row.fetchAll(db, sql: "SELECT note_id, tag FROM tags")
            
            for row in tagRows {
                let noteId: String = row["note_id"]
                dbTagsById[noteId, default: []].insert(row["tag"])
            }
            
            let ftsIds = Set(try String.fetchAll(db, sql: "SELECT DISTINCT id FROM notes_fts"))
            let noteIds = Set(dbRows.values.map { row in row.id })
            
            for (relativePath, file) in filesByRel {
                guard let row = dbRows[relativePath] else { continue }
                
                let fields: FrontmatterDoc
                let text: String
                do {
                    text = try String(contentsOf: file, encoding: .utf8)
                    (fields, _) = try Frontmatter.parse(text)
                } catch {
                    messages.append("L2\tfrontmatter-parse\t\(relativePath)\t\(error)")
                    ok = false
                    continue
                }
                
                for (fieldName, dbValue) in [
                    ("title", row.title),
                    ("summary", row.summary ?? ""),
                    ("axis", row.axis),
                    ("priority", row.priority)
                ] {
                    let fileValue: String
                    switch fieldName {
                    case "title":
                        fileValue = fields.title
                    
                    case "summary":
                        fileValue = fields.summary
                    
                    case "axis":
                        fileValue = fields.axis
                    
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
                
                if Notes.contentHash(text) != row.contentHash {
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
            
            let axesSet = Set(try String.fetchAll(db, sql: "SELECT axis FROM axes"))
            let vocabSet = Set(try String.fetchAll(db, sql: "SELECT tag FROM tag_vocab"))
            
            for (_, row) in dbRows {
                let noteId = row.id
                let nsNoteId = noteId as NSString
                
                if idRegex.firstMatch(
                    in: noteId,
                    range: NSRange(location: 0, length: nsNoteId.length)
                ) == nil {
                    messages.append("L3\tinvalid-id\t\(noteId)\t(kebab-case required)")
                    ok = false
                }
                
                if !["eager", "lazy"].contains(row.priority) {
                    messages.append("L3\tinvalid-priority\t\(noteId)\t\(row.priority)")
                    ok = false
                }
                
                if !axesSet.contains(row.axis) {
                    messages.append("L3\taxis-unregistered\t\(noteId)\taxis=\(row.axis)")
                    ok = false
                }
                
                let tags = dbTagsById[noteId] ?? []
                
                if !tags.contains(row.axis) {
                    messages.append(
                        "L3\taxis-tag-missing\t\(noteId)\taxis=\(row.axis) tags=\(tags.sorted())"
                    )
                    ok = false
                }
                
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
            
            for kind in linkKinds where !Links.allKinds.contains(kind) {
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
}
