//
//  FetchDeliberateNeighborsTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct FetchDeliberateNeighborsTransaction: GRDBReadTransaction {
    // MARK: - Property
    let noteId: String

    // MARK: - Initializer
    init(noteId: String) {
        self.noteId = noteId
    }

    // MARK: - Public
    func perform(_ db: Database) throws -> [String] {
        let deliberate = Links.deleteBlockingKinds
        let kindPlaceholders = Array(repeating: "?", count: deliberate.count)
            .joined(separator: ",")
        let arguments: [DatabaseValueConvertible?] = [noteId, noteId, noteId]
            + (Array(deliberate) as [DatabaseValueConvertible?])

        return try String.fetchAll(db, sql: """
            SELECT CASE WHEN src = ? THEN dst ELSE src END AS other FROM note_links
            WHERE (src = ? OR dst = ?) AND kind IN (\(kindPlaceholders))
            """, arguments: StatementArguments(arguments))
    }

    // MARK: - Private
}
