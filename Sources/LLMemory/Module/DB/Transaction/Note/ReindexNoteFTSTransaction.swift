//
//  ReindexNoteFTSTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

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
