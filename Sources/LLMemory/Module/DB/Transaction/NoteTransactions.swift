//
//  NoteTransactions.swift
//  LLMemory
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import GRDB

// notes-row transactions — the core catalog row, its FTS projection,
// reference links, and lifecycle provenance. File-level note reading stays
// in the Notes module.
struct UpsertNoteTransaction: GRDBTransaction {
    // MARK: - Property
    let file: URL
    let fields: FrontmatterDoc
    let body: String
    let raw: String?
    let now: Int

    // MARK: - Initializer
    init(file: URL, fields: FrontmatterDoc, body: String, raw: String? = nil, now: Int) {
        self.file = file
        self.fields = fields
        self.body = body
        self.raw = raw
        self.now = now
    }

    // MARK: - Public
    @discardableResult
    func perform(_ db: Database) throws -> String {
        // The file's location is the id. Whatever the caller carried in `fields`
        // is not consulted here — there is one source, so there is nothing to
        // reconcile and no way for a row to point somewhere its file is not.
        guard let noteId = Paths.id(ofFile: file), !noteId.isEmpty else {
            throw NotesError.notALiveNote(
                path: Paths.relative(of: file) ?? file.path,
                reason: Paths.liveNoteRejection(of: file)
                    ?? Paths.addressRejection(of: file)
                    ?? "not addressable"
            )
        }

        let priority = fields.priority.isEmpty ? "lazy" : fields.priority

        guard ["eager", "lazy"].contains(priority) else {
            throw NotesError.invalidPriority(priority)
        }

        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        let mtime = Int((attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0)

        let staleFlag = fields.stale ? 1 : 0
        let templateValue = fields.template.flatMap { value in value.isEmpty ? nil : value }
        let lockedFlag = fields.locked ? 1 : 0
        let seedFlag = fields.seed ? 1 : 0
        let wordCount = SectionEdit.wordCount(body)
        let sectionCount = SectionEdit.sectionCount(body)
        let contentHash = Notes.contentHash(
            try raw ?? String(contentsOf: file, encoding: .utf8)
        )

        try db.execute(sql: """
            INSERT INTO notes (id, title, summary, priority,
                               stale, template, locked, seed,
                               edited_at, word_count, section_count, content_hash)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
              title=excluded.title, summary=excluded.summary,
              priority=excluded.priority,
              stale=excluded.stale,
              template=excluded.template, locked=excluded.locked,
              seed=excluded.seed,
              edited_at=excluded.edited_at,
              word_count=excluded.word_count,
              section_count=excluded.section_count,
              content_hash=excluded.content_hash
            """, arguments: [
                noteId,
                fields.title, fields.summary,
                priority, staleFlag,
                templateValue, lockedFlag, seedFlag,
                mtime, wordCount, sectionCount, contentHash
            ])
        try db.execute(
            sql: "INSERT OR IGNORE INTO note_usage (note_id, created_at) VALUES (?, ?)",
            arguments: [noteId, mtime]
        )
        try ProjectNoteRefsTransaction(noteId: noteId, paths: fields.source, now: now).perform(db)
        try db.execute(sql: "DELETE FROM tags WHERE note_id = ?", arguments: [noteId])

        for tag in fields.tags {
            let canonical = try CanonicalizeTagTransaction(tag: tag).perform(db)

            try EnsureTagTransaction(tag: canonical, now: now).perform(db)
            try db.execute(
                sql: "INSERT OR IGNORE INTO tags (note_id, tag) VALUES (?, ?)",
                arguments: [noteId, canonical]
            )
        }

        try db.execute(sql: "DELETE FROM note_extra WHERE note_id = ?", arguments: [noteId])

        for key in fields.extra.keys.sorted() {
            try db.execute(
                sql: "INSERT INTO note_extra (note_id, key, value) VALUES (?, ?, ?)",
                arguments: [noteId, key, fields.extra[key]]
            )
        }

        try ReconcileNoteEntitiesTransaction(
            entities: fields.entities ?? [],
            noteId: noteId,
            now: now
        )
            .perform(db)
        try ReindexNoteFTSTransaction(
            noteId: noteId,
            title: fields.title,
            summary: fields.summary,
            body: body
        )
            .perform(db)
        try RefreshReferenceLinksTransaction(nid: noteId, body: body, now: now).perform(db)

        return noteId
    }

    // MARK: - Private
}

struct ReindexNoteFTSTransaction: GRDBTransaction {
    // MARK: - Property
    let noteId: String
    let title: String
    let summary: String?
    let body: String

    // MARK: - Initializer
    init(noteId: String, title: String, summary: String?, body: String) {
        self.noteId = noteId
        self.title = title
        self.summary = summary
        self.body = body
    }

    // MARK: - Public
    func perform(_ db: Database) throws {
        let enrich = try FetchNoteEnrichTextTransaction(noteId: noteId).perform(db)
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

    // MARK: - Private
}

struct FetchNoteEnrichTextTransaction: GRDBReadTransaction {
    // MARK: - Property
    let noteId: String

    // MARK: - Initializer
    init(noteId: String) {
        self.noteId = noteId
    }

    // MARK: - Public
    func perform(_ db: Database) throws -> String {
        let terms = try String.fetchAll(db, sql: """
            SELECT term FROM note_retrieval_terms
            WHERE note_id = ? AND status = 'active'
            ORDER BY kind, term
            """, arguments: [noteId])

        return terms.joined(separator: "\n")
    }

    // MARK: - Private
}

struct SyncNoteEnrichTransaction: GRDBTransaction {
    // MARK: - Property
    let noteId: String

    // MARK: - Initializer
    init(noteId: String) {
        self.noteId = noteId
    }

    // MARK: - Public
    func perform(_ db: Database) throws {
        guard try NoteExistsTransaction(nid: noteId).perform(db) else { return }

        let enrich = try FetchNoteEnrichTextTransaction(noteId: noteId).perform(db)

        try db.execute(
            sql: "UPDATE notes_fts SET enrich = ? WHERE id = ? AND section = ''",
            arguments: [enrich, noteId]
        )
    }

    // MARK: - Private
}

struct RefreshReferenceLinksTransaction: GRDBTransaction {
    // MARK: - Property
    let nid: String
    let body: String
    let now: Int

    // MARK: - Initializer
    init(nid: String, body: String, now: Int) {
        self.nid = nid
        self.body = body
        self.now = now
    }

    // MARK: - Public
    func perform(_ db: Database) throws {
        let nsBody = body as NSString
        let range = NSRange(location: 0, length: nsBody.length)
        var candidates = Set<String>()

        for regex in [Notes.backtickIdRegex, Notes.wikilinkRegex] {
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

    // MARK: - Private
}

// Who cites this id — whether or not the citation currently resolves.
struct FetchCitingNoteIdsTransaction: GRDBReadTransaction {
    // MARK: - Property
    let marker: String

    // MARK: - Initializer
    init(marker: String) {
        self.marker = marker
    }

    // MARK: - Public
    func perform(_ db: Database) throws -> [String] {
        try String.fetchAll(
            db,
            sql: "SELECT DISTINCT src FROM note_ref_markers WHERE marker = ? ORDER BY src",
            arguments: [marker]
        )
    }

    // MARK: - Private
}

// Re-addressing is renaming, and a rename that leaves the corpus pointing at
// the old name is a rename that manufactures dangling references. There is no
// alias table to soften this: the citations themselves move, so the resolver
// stays a single exact match and no old name outlives the note.
//
// note_ref_markers is what makes it tractable — it records who cites whom
// whether or not the citation resolved, so the set of files to touch is known
// rather than searched for.
struct RewriteInboundCitationsTransaction: GRDBTransaction {
    // MARK: - Property
    let from: String
    let to: String

    // MARK: - Initializer
    init(from: String, to: String) {
        self.from = from
        self.to = to
    }

    // MARK: - Public
    @discardableResult
    func perform(_ db: Database) throws -> [String] {
        guard from != to else { return [] }

        let referrers = try String.fetchAll(
            db,
            sql: "SELECT DISTINCT src FROM note_ref_markers WHERE marker = ? AND src != ?",
            arguments: [from, to]
        )
        var rewritten: [String] = []

        for src in referrers.sorted() {
            let file = Paths.file(forId: src)
            // Not `try?`. With no alias table, a citation this loop fails to
            // rewrite is a reference that breaks — reporting success while
            // leaving one behind is the exact state the design forbids, so an
            // unreadable citer fails the whole re-addressing instead.
            let text = try String(contentsOf: file, encoding: .utf8)

            // Both citation forms, because the resolver treats them as one.
            let updated = text
                .replacingOccurrences(of: "`\(from)`", with: "`\(to)`")
                .replacingOccurrences(of: "[[\(from)]]", with: "[[\(to)]]")

            guard updated != text else { continue }

            try updated.write(to: file, atomically: true, encoding: .utf8)
            try ReindexNoteFileTransaction(path: file).perform(db)
            rewritten.append(src)
        }

        return rewritten
    }

    // MARK: - Private
}

struct ActivateNotesTransaction: GRDBTransaction {
    // MARK: - Property
    let ids: [String]
    let now: Int

    // MARK: - Initializer
    init(ids: [String], now: Int) {
        self.ids = ids
        self.now = now
    }

    // MARK: - Public
    func perform(_ db: Database) throws {
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

    // MARK: - Private
}

struct DeleteNoteRowTransaction: GRDBTransaction {
    // MARK: - Property
    let nid: String

    // MARK: - Initializer
    init(nid: String) {
        self.nid = nid
    }

    // MARK: - Public
    func perform(_ db: Database) throws {
        try db.execute(sql: "DELETE FROM notes WHERE id = ?", arguments: [nid])
        try db.execute(sql: "DELETE FROM notes_fts WHERE id = ?", arguments: [nid])
    }

    // MARK: - Private
}

struct NoteExistsTransaction: GRDBReadTransaction {
    // MARK: - Property
    let nid: String

    // MARK: - Initializer
    init(nid: String) {
        self.nid = nid
    }

    // MARK: - Public
    func perform(_ db: Database) throws -> Bool {
        try Int.fetchOne(db, sql: "SELECT 1 FROM notes WHERE id = ?", arguments: [nid]) != nil
    }

    // MARK: - Private
}

struct FetchNotePathTransaction: GRDBReadTransaction {
    // MARK: - Property
    let nid: String

    // MARK: - Initializer
    init(nid: String) {
        self.nid = nid
    }

    // MARK: - Public
    // Existence is the only thing the DB is asked — where the note lives is a
    // function of its id, so nil here means "no such note", never "no path".
    func perform(_ db: Database) throws -> URL? {
        guard try NoteExistsTransaction(nid: nid).perform(db) else { return nil }

        return Paths.file(forId: nid)
    }

    // MARK: - Private
}

struct FetchNoteIdsTransaction: GRDBReadTransaction {
    // MARK: - Initializer
    init() { }

    // MARK: - Public
    func perform(_ db: Database) throws -> Set<String> {
        Set(try String.fetchAll(db, sql: "SELECT id FROM notes"))
    }

    // MARK: - Private
}

struct CountEagerNotesTransaction: GRDBReadTransaction {
    // MARK: - Initializer
    init() { }

    // MARK: - Public
    func perform(_ db: Database) throws -> Int {
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM notes WHERE \(Policy.eager(""))") ?? 0
    }

    // MARK: - Private
}

struct SetNoteStaleTransaction: GRDBTransaction {
    // MARK: - Property
    let nid: String
    let stale: Bool

    // MARK: - Initializer
    init(nid: String, stale: Bool) {
        self.nid = nid
        self.stale = stale
    }

    // MARK: - Public
    func perform(_ db: Database) throws {
        try db.execute(
            sql: "UPDATE notes SET stale = ? WHERE id = ?",
            arguments: [stale ? 1 : 0, nid]
        )
    }

    // MARK: - Private
}

struct RecordNoteLifecycleEventTransaction: GRDBTransaction {
    // MARK: - Property
    let nid: String
    let kind: String
    let reason: String?
    let now: Int

    // MARK: - Initializer
    init(nid: String, kind: String, reason: String?, now: Int) {
        self.nid = nid
        self.kind = kind
        self.reason = reason
        self.now = now
    }

    // MARK: - Public
    func perform(_ db: Database) throws {
        let trimmedReason = reason.map { text in String(text.prefix(200)) }

        try db.execute(sql: """
            INSERT INTO note_lifecycle_events (note_id, kind, reason, created_at)
            VALUES (?, ?, ?, ?)
            """, arguments: [nid, kind, trimmedReason, now])
    }

    // MARK: - Private
}

struct StampNoteLifecycleTransaction: GRDBTransaction {
    // MARK: - Property
    let nid: String
    let now: Int
    let isNew: Bool

    // MARK: - Initializer
    init(nid: String, now: Int, isNew: Bool) {
        self.nid = nid
        self.now = now
        self.isNew = isNew
    }

    // MARK: - Public
    func perform(_ db: Database) throws {
        guard try NoteExistsTransaction(nid: nid).perform(db) else {
            throw NotesError.stampedFileVanished(nid: nid, path: "(no notes row)")
        }

        let relativePath = Paths.relativeFile(forId: nid)
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

    // MARK: - Private
}

struct ClearNoteFTSTransaction: GRDBTransaction {
    // MARK: - Property
    let nid: String

    // MARK: - Initializer
    init(nid: String) {
        self.nid = nid
    }

    // MARK: - Public
    func perform(_ db: Database) throws {
        try db.execute(sql: "DELETE FROM notes_fts WHERE id = ?", arguments: [nid])
    }

    // MARK: - Private
}

struct SetNoteFTSMetaOnlyTransaction: GRDBTransaction {
    // MARK: - Property
    let nid: String
    let title: String
    let summary: String?

    // MARK: - Initializer
    init(nid: String, title: String, summary: String?) {
        self.nid = nid
        self.title = title
        self.summary = summary
    }

    // MARK: - Public
    func perform(_ db: Database) throws {
        try ReindexNoteFTSTransaction(noteId: nid, title: title, summary: summary ?? "", body: "")
            .perform(db)
    }

    // MARK: - Private
}

struct FetchNoteTransaction: GRDBReadTransaction {
    // MARK: - Property
    let nid: String

    // MARK: - Initializer
    init(nid: String) {
        self.nid = nid
    }

    // MARK: - Public
    func perform(_ db: Database) throws -> (URL, FrontmatterDoc, String)? {
        guard try NoteExistsTransaction(nid: nid).perform(db) else { return nil }

        let path = Paths.file(forId: nid)
        let text = try String(contentsOf: path, encoding: .utf8)
        let (fields, body) = try Frontmatter.parse(text)

        return (path, fields, body)
    }

    // MARK: - Private
}

struct ReindexNoteFileTransaction: GRDBTransaction {
    // MARK: - Property
    let path: URL

    // MARK: - Initializer
    init(path: URL) {
        self.path = path
    }

    // MARK: - Public
    @discardableResult
    func perform(_ db: Database) throws -> String {
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

        return try UpsertNoteTransaction(file: path, fields: fields, body: body, raw: text, now: now)
            .perform(db)
    }

    // MARK: - Private
    private func normalizeTags(
        _ db: Database,
        _ doc: inout FrontmatterDoc
    ) throws -> Bool {
        guard !doc.tags.isEmpty else { return false }

        var seen = Set<String>()
        var normalized: [String] = []

        for tag in doc.tags {
            let canonical = try CanonicalizeTagTransaction(tag: tag).perform(db)

            if seen.insert(canonical).inserted { normalized.append(canonical) }
        }

        if normalized == doc.tags { return false }

        doc.tags = normalized

        return true
    }
}
