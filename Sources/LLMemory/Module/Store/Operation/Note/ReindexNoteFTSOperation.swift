//
//  ReindexNoteFTSOperation.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct ReindexNoteFTSOperation: GRDBOperation {
    // MARK: - Property
    typealias Parameter = (String, String, String?, String)
    let noteId: String
    let title: String
    let summary: String?
    let body: String

    private let sectionEdit = SectionEdit()

    // MARK: - Initializer
    init(noteId: String, title: String, summary: String?, body: String) {
        self.noteId = noteId
        self.title = title
        self.summary = summary
        self.body = body
    }

    // MARK: - Public
    func execute(_ db: Database) throws {
        let enrich = try FetchNoteEnrichTextOperation(noteId: noteId).execute(db)
        let (_, rows) = sectionEdit.sectionRows(body)

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
