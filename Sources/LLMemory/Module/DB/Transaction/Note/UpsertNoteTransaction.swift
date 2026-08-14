//
//  UpsertNoteTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
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
