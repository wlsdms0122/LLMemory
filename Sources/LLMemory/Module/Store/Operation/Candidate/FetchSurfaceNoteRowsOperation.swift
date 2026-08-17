//
//  FetchSurfaceNoteRowsOperation.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct FetchSurfaceNoteRowsOperation: GRDBReadOperation {
    struct SurfaceNote {
        // MARK: - Property
        let id: String
        let title: String
        let summary: String?

        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }

    // MARK: - Initializer
    init() { }

    // MARK: - Public
    func execute(_ db: Database) throws -> [SurfaceNote] {
        try Row.fetchAll(db, sql: """
            SELECT id, title, summary FROM notes
            WHERE \(Policy.all(Policy.surface(""), Policy.forgetExempt("")))
            ORDER BY id
            """).map { row in
            SurfaceNote(
                id: row["id"],
                title: row["title"],
                summary: row["summary"] as String?
            )
        }
    }

    // MARK: - Private
}
