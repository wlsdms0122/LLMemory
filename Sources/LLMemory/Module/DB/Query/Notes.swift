//
//  Notes.swift
//  LLMemory
//
//  Created by JSilver on 8/7/26.
//

import Foundation
import GRDB
import CryptoKit

enum Notes {
    // MARK: - Property
    private static let wikilinkRegex = try! NSRegularExpression(
        pattern: #"\[\[([a-z0-9][a-z0-9-]*)\]\]"#
    )
    private static let backtickIdRegex = try! NSRegularExpression(
        pattern: #"`([a-z][a-z0-9-]{2,})`"#
    )
    
    // MARK: - Initializer
    // MARK: - Public
    static func contentHash(_ text: String) -> String {
        let digest = SHA256.hash(data: text.data(using: .utf8) ?? Data())
        
        return String(digest.map { byte in String(format: "%02x", byte) }.joined().prefix(16))
    }
    
    static func requireNote(at url: URL) throws -> (doc: FrontmatterDoc, body: String) {
        guard let read = try readNoteIfPresent(at: url) else {
            throw NoteUnreadable(path: url.path, reason: "file does not exist")
        }
        
        return read
    }
    
    static func readNoteIfPresent(at url: URL) throws -> (doc: FrontmatterDoc, body: String)? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        
        do {
            return try Frontmatter.parse(try String(contentsOf: url, encoding: .utf8))
        } catch {
            throw NoteUnreadable(path: url.path, reason: "\(error)")
        }
    }
    
    static func relativeToBrainRoot(_ file: URL) throws -> String {
        guard let relativePath = Paths.relative(of: file) else {
            throw NotesError.notUnderBrainRoot(file.path)
        }
        
        return relativePath
    }
    
    @discardableResult
    static func upsert(
        _ db: Database,
        file: URL,
        fields: FrontmatterDoc,
        body: String,
        raw: String? = nil,
        now: Int
    ) throws -> String {
        if fields.id.isEmpty { throw NotesError.idMissing }
        
        var axis = fields.axis
        
        if axis.isEmpty { axis = Paths.axisFromPath(file) }
        
        let priority = fields.priority.isEmpty ? "lazy" : fields.priority
        
        guard ["eager", "lazy"].contains(priority) else {
            throw NotesError.invalidPriority(priority)
        }
        
        let relativePath = try Notes.relativeToBrainRoot(file)
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        let mtime = Int((attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0)
        
        try Vocab.ensureAxis(db, axis: axis, now: now)
        
        let staleFlag = fields.stale ? 1 : 0
        let templateValue = fields.template.flatMap { value in value.isEmpty ? nil : value }
        let lockedFlag = fields.locked ? 1 : 0
        let wordCount = SectionEdit.wordCount(body)
        let sectionCount = SectionEdit.sectionCount(body)
        let contentHash = Notes.contentHash(
            try raw ?? String(contentsOf: file, encoding: .utf8)
        )
        
        try db.execute(sql: """
            INSERT INTO notes (id, axis, path, title, summary, priority,
                               file_mtime, indexed_at, stale,
                               template, locked,
                               edited_at, word_count, section_count, content_hash)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
              axis=excluded.axis, path=excluded.path,
              title=excluded.title, summary=excluded.summary,
              priority=excluded.priority,
              file_mtime=excluded.file_mtime, indexed_at=excluded.indexed_at,
              stale=excluded.stale,
              template=excluded.template, locked=excluded.locked,
              edited_at=excluded.edited_at,
              word_count=excluded.word_count,
              section_count=excluded.section_count,
              content_hash=excluded.content_hash
            """, arguments: [
                fields.id, axis, relativePath,
                fields.title, fields.summary,
                priority, mtime, now, staleFlag,
                templateValue, lockedFlag,
                mtime, wordCount, sectionCount, contentHash
            ])
        try db.execute(
            sql: "INSERT OR IGNORE INTO note_usage (note_id, created_at) VALUES (?, ?)",
            arguments: [fields.id, mtime]
        )
        try SourcesService.projectRefs(db, noteId: fields.id, paths: fields.source, now: now)
        try db.execute(sql: "DELETE FROM tags WHERE note_id = ?", arguments: [fields.id])
        
        for tag in fields.tags {
            let canonical = try Vocab.canonicalizeTag(db, tag: tag)
            
            try Vocab.ensureTag(db, tag: canonical, now: now)
            try db.execute(
                sql: "INSERT OR IGNORE INTO tags (note_id, tag) VALUES (?, ?)",
                arguments: [fields.id, canonical]
            )
        }
        
        try Entities.reconcile(
            db,
            entities: fields.entities ?? [],
            noteId: fields.id,
            now: now
        )
        try reindexFTS(
            db,
            noteId: fields.id,
            title: fields.title,
            summary: fields.summary,
            body: body
        )
        try refreshReferenceLinks(db, nid: fields.id, body: body, now: now)
        
        return fields.id
    }
    
    static func reindexFTS(
        _ db: Database,
        noteId: String,
        title: String,
        summary: String?,
        body: String
    ) throws {
        let enrich = try enrichText(db, noteId: noteId)
        let (_, rows) = SectionEdit.sectionRows(body)
        
        try db.execute(sql: "DELETE FROM notes_fts WHERE id = ?", arguments: [noteId])
        try db.execute(sql: """
            INSERT INTO notes_fts (id, section, title, summary, body, enrich)
            VALUES (?, '', ?, ?, ?, ?)
            """, arguments: [noteId, title, summary, body.trimmingTrailingNewlines(), enrich])
        
        for row in rows {
            try db.execute(sql: """
                INSERT INTO notes_fts (id, section, title, summary, body, enrich)
                VALUES (?, ?, '', '', ?, '')
                """, arguments: [noteId, row.path, row.text])
        }
    }
    
    static func enrichText(_ db: Database, noteId: String) throws -> String {
        let terms = try String.fetchAll(db, sql: """
            SELECT term FROM note_retrieval_terms
            WHERE note_id = ? AND status = 'active'
            ORDER BY kind, term
            """, arguments: [noteId])
        
        return terms.joined(separator: "\n")
    }
    
    static func syncEnrich(_ db: Database, noteId: String) throws {
        guard try exists(db, nid: noteId) else { return }
        
        let enrich = try enrichText(db, noteId: noteId)
        
        try db.execute(
            sql: "UPDATE notes_fts SET enrich = ? WHERE id = ? AND section = ''",
            arguments: [enrich, noteId]
        )
    }
    
    static func refreshReferenceLinks(
        _ db: Database,
        nid: String,
        body: String,
        now: Int
    ) throws {
        let nsBody = body as NSString
        let range = NSRange(location: 0, length: nsBody.length)
        var candidates = Set<String>()
        
        for regex in [backtickIdRegex, wikilinkRegex] {
            regex.enumerateMatches(in: body, range: range) { match, _, _ in
                guard let match else { return }
                
                candidates.insert(nsBody.substring(with: match.range(at: 1)))
            }
        }
        
        candidates.remove(nid)
        
        try db.execute(sql: "DELETE FROM note_ref_markers WHERE src = ?", arguments: [nid])
        
        for marker in candidates.sorted() {
            try db.execute(sql: """
                INSERT INTO note_ref_markers (src, marker, created_at) VALUES (?, ?, ?)
                """, arguments: [nid, marker, now])
        }
        
        try db.execute(
            sql: "DELETE FROM note_links WHERE src = ? AND kind = ?",
            arguments: [nid, Links.kindReference]
        )
        try db.execute(sql: """
            INSERT OR IGNORE INTO note_links (src, dst, kind, weight, created_at, last_activated_at)
            SELECT m.src, n.id, ?, 1.0, ?, ?
            FROM note_ref_markers m JOIN notes n ON n.id = m.marker
            WHERE m.src = ?
            """, arguments: [Links.kindReference, now, now, nid])
        try db.execute(sql: """
            INSERT OR IGNORE INTO note_links (src, dst, kind, weight, created_at, last_activated_at)
            SELECT m.src, ?, ?, 1.0, ?, ?
            FROM note_ref_markers m JOIN notes s ON s.id = m.src
            WHERE m.marker = ? AND m.src != ?
            """, arguments: [nid, Links.kindReference, now, now, nid, nid])
    }
    
    static func activate(_ db: Database, ids: [String], now: Int) throws {
        guard !ids.isEmpty else { return }
        
        for noteId in ids {
            try db.execute(sql: """
                INSERT INTO note_usage (note_id, hit_count, last_retrieved_at, created_at)
                VALUES (?, 1, ?, ?)
                ON CONFLICT(note_id) DO UPDATE SET
                  hit_count = hit_count + 1,
                  last_retrieved_at = excluded.last_retrieved_at
                """, arguments: [noteId, now, now])
            try db.execute(sql: """
                UPDATE entity_index SET last_seen_at = ?, hit_count = hit_count + 1
                WHERE note_id = ?
                """, arguments: [now, noteId])
        }
    }
    
    static func delete(_ db: Database, nid: String) throws {
        try db.execute(sql: "DELETE FROM notes WHERE id = ?", arguments: [nid])
        try db.execute(sql: "DELETE FROM notes_fts WHERE id = ?", arguments: [nid])
    }
    
    static func exists(_ db: Database, nid: String) throws -> Bool {
        try Int.fetchOne(db, sql: "SELECT 1 FROM notes WHERE id = ?", arguments: [nid]) != nil
    }
    
    static func pathOf(_ db: Database, nid: String) throws -> URL? {
        guard let relativePath = try String.fetchOne(
            db,
            sql: "SELECT path FROM notes WHERE id = ?",
            arguments: [nid]
        ) else {
            return nil
        }
        
        return Paths.brainRoot.appendingPathComponent(relativePath)
    }
    
    static func listByAxis(_ db: Database, axis: String) throws -> [(id: String, path: String)] {
        let rows = try Row.fetchAll(
            db,
            sql: "SELECT id, path FROM notes WHERE axis = ?",
            arguments: [axis]
        )
        
        return rows.map { row in (id: row["id"], path: row["path"]) }
    }
    
    static func existingIds(_ db: Database) throws -> Set<String> {
        Set(try String.fetchAll(db, sql: "SELECT id FROM notes"))
    }
    
    static func eagerCount(_ db: Database) throws -> Int {
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM notes WHERE \(Policy.eager(""))") ?? 0
    }
    
    static func allPathsRel(_ db: Database) throws -> [(id: String, path: String)] {
        let rows = try Row.fetchAll(db, sql: "SELECT id, path FROM notes")
        
        return rows.map { row in (id: row["id"], path: row["path"]) }
    }
    
    static func setAxis(_ db: Database, fromAxis: String, toAxis: String) throws -> Int {
        try db.execute(
            sql: "UPDATE notes SET axis = ? WHERE axis = ?",
            arguments: [toAxis, fromAxis]
        )
        
        return db.changesCount
    }
    
    static func setPath(
        _ db: Database,
        nid: String,
        newRel: String,
        fileMtime: Int,
        indexedAt: Int
    ) throws {
        try db.execute(
            sql: "UPDATE notes SET path = ?, file_mtime = ?, indexed_at = ? WHERE id = ?",
            arguments: [newRel, fileMtime, indexedAt, nid]
        )
    }
    
    static func setStale(_ db: Database, nid: String, stale: Bool) throws {
        try db.execute(
            sql: "UPDATE notes SET stale = ? WHERE id = ?",
            arguments: [stale ? 1 : 0, nid]
        )
    }
    
    static func recordLifecycleEvent(
        _ db: Database,
        nid: String,
        kind: String,
        reason: String?,
        now: Int
    ) throws {
        let trimmedReason = reason.map { text in String(text.prefix(200)) }
        
        try db.execute(sql: """
            INSERT INTO note_lifecycle_events (note_id, kind, reason, created_at)
            VALUES (?, ?, ?, ?)
            """, arguments: [nid, kind, trimmedReason, now])
    }
    
    static func stampLifecycle(
        _ db: Database,
        nid: String,
        now: Int,
        isNew: Bool
    ) throws {
        guard let row = try Row.fetchOne(
            db,
            sql: "SELECT path FROM notes WHERE id = ?",
            arguments: [nid]
        ) else {
            throw NotesError.stampedFileVanished(nid: nid, path: "(no notes row)")
        }
        
        let relativePath: String = row["path"]
        let previousCreated = (try Int.fetchOne(
            db,
            sql: "SELECT created_at FROM note_usage WHERE note_id = ?",
            arguments: [nid]
        )) ?? 0
        let path = Paths.brainRoot.appendingPathComponent(relativePath)
        let (_, body) = try Notes.requireNote(at: path)
        let wordCount = SectionEdit.wordCount(body)
        let sectionCount = SectionEdit.sectionCount(body)
        var created = previousCreated != 0 ? previousCreated : now
        
        if isNew { created = now }
        
        try db.execute(
            sql: "UPDATE notes SET edited_at = ?, word_count = ?, section_count = ? WHERE id = ?",
            arguments: [now, wordCount, sectionCount, nid]
        )
        try db.execute(sql: """
            INSERT INTO note_usage (note_id, created_at) VALUES (?, ?)
            ON CONFLICT(note_id) DO UPDATE SET created_at = excluded.created_at
            """, arguments: [nid, created])
    }
    
    static func ftsClear(_ db: Database, nid: String) throws {
        try db.execute(sql: "DELETE FROM notes_fts WHERE id = ?", arguments: [nid])
    }
    
    static func ftsSetMetaOnly(
        _ db: Database,
        nid: String,
        title: String,
        summary: String?
    ) throws {
        try reindexFTS(db, noteId: nid, title: title, summary: summary ?? "", body: "")
    }
    
    static func get(_ db: Database, nid: String) throws -> (URL, FrontmatterDoc, String)? {
        guard let relativePath = try String.fetchOne(
            db,
            sql: "SELECT path FROM notes WHERE id = ?",
            arguments: [nid]
        ) else {
            return nil
        }
        
        let path = Paths.brainRoot.appendingPathComponent(relativePath)
        let text = try String(contentsOf: path, encoding: .utf8)
        let (fields, body) = try Frontmatter.parse(text)
        
        return (path, fields, body)
    }
    
    @discardableResult
    static func reindexFile(_ db: Database, path: URL) throws -> String {
        if let rejection = Paths.liveNoteRejection(of: path) {
            throw NotesError.notALiveNote(
                path: Paths.relative(of: path) ?? path.path,
                reason: rejection
            )
        }
        
        let now = Int(Date().timeIntervalSince1970)

        var text = try String(contentsOf: path, encoding: .utf8)
        var (fields, body) = try Frontmatter.parse(text)
        let tagsChanged = try normalizeTags(db, &fields)
        
        if tagsChanged {
            text = Frontmatter.dump(fields) + body
            try text.write(to: path, atomically: true, encoding: .utf8)
        }
        
        return try upsert(db, file: path, fields: fields, body: body, raw: text, now: now)
    }
    
    // MARK: - Private
    private static func normalizeTags(
        _ db: Database,
        _ doc: inout FrontmatterDoc
    ) throws -> Bool {
        guard !doc.tags.isEmpty else { return false }
        
        var seen = Set<String>()
        var normalized: [String] = []
        
        for tag in doc.tags {
            let canonical = try Vocab.canonicalizeTag(db, tag: tag)
            
            if seen.insert(canonical).inserted { normalized.append(canonical) }
        }
        
        if normalized == doc.tags { return false }
        
        doc.tags = normalized
        
        return true
    }
}

struct NoteUnreadable: Error, CustomStringConvertible {
    // MARK: - Property
    let path: String
    let reason: String
    
    var description: String { "unreadable note file \(path): \(reason)" }
    
    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}

enum NotesError: Error, CustomStringConvertible {
    case idMissing
    case invalidPriority(String)
    case notUnderBrainRoot(String)
    case notALiveNote(path: String, reason: String)
    case unknownIds([String])
    case trashUnreadable(nid: String, files: [String], matched: Bool)
    case stampedFileVanished(nid: String, path: String)
    case noteFileMissing(path: String)
    
    var description: String {
        switch self {
        case .idMissing:
            return "id missing"
        
        case .invalidPriority(let priority):
            return "invalid priority: \(priority)"
        
        case .notUnderBrainRoot(let path):
            return "file not under BRAIN_ROOT: \(path)"
        
        case .notALiveNote(let path, let reason):
            return "not a live note: \(path) — \(reason)"
        
        case .unknownIds(let ids):
            return "unknown id: \(ids.joined(separator: ", "))"
        
        case .noteFileMissing(let path):
            return "note file does not exist: \(path)"
        
        case .stampedFileVanished(let nid, let path):
            return "note file vanished between write and stamp: \(nid) → \(path)"
        
        case .trashUnreadable(let nid, let files, let matched):
            let why = matched
                ? "a readable incarnation of '\(nid)' was found, but an unreadable trash file may be a "
                    + "later one — restoring the readable one would quietly bring back an older version"
                : "one of them may be '\(nid)' itself, so 'not in trash' would be a guess"
            
            return "cannot resolve '\(nid)' in trash — \(files.count) trash file(s) unreadable; "
                + why + ": \(files.joined(separator: "; "))"
        }
    }
}
