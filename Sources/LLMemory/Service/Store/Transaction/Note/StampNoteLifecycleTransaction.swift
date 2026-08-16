//
//  StampNoteLifecycleTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct StampNoteLifecycleTransaction: GRDBBrainTransaction {
    // MARK: - Property
    let nid: String
    let now: Int
    let isNew: Bool

    private let sectionEdit = SectionEdit()

    private let noteFile = NoteFile()

    // MARK: - Initializer
    init(nid: String, now: Int, isNew: Bool) {
        self.nid = nid
        self.now = now
        self.isNew = isNew
    }

    // MARK: - Public
    func perform(_ db: Database, _ brain: BrainContext) throws {
        guard try NoteExistsTransaction(nid: nid).perform(db) else {
            throw NotesError.stampedFileVanished(nid: nid, path: "(no notes row)")
        }

        let relativePath = brain.path.relativeFile(forId: nid)
        let previousCreated = (try Int.fetchOne(
            db,
            sql: "SELECT created_at FROM note_usage WHERE note_id = ?",
            arguments: [nid]
        )) ?? 0
        let path = brain.path.brainRoot.appendingPathComponent(relativePath)
        let (_, body) = try noteFile.requireNote(at: path)
        let wordCount = sectionEdit.wordCount(body)
        let sectionCount = sectionEdit.sectionCount(body)
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
