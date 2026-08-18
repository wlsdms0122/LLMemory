//
//  FetchDeliberateNeighborsOperation.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct FetchDeliberateNeighborsOperation: GRDBReadOperation {
    // MARK: - Property
    typealias Parameter = String
    let noteId: String

    // MARK: - Initializer
    init(noteId: String) {
        self.noteId = noteId
    }

    // MARK: - Public
    func execute(_ db: Database) throws -> [String] {
        let deliberate = LinkKind.rawValues { kind in kind.blocksDelete }
        let kindPlaceholders = Array(repeating: "?", count: deliberate.count)
            .joined(separator: ",")
        let arguments: [DatabaseValueConvertible?] = [noteId, noteId, noteId]
            + (deliberate as [DatabaseValueConvertible?])

        return try String.fetchAll(db, sql: """
            SELECT CASE WHEN src = ? THEN dst ELSE src END AS other FROM note_links
            WHERE (src = ? OR dst = ?) AND kind IN (\(kindPlaceholders))
            """, arguments: StatementArguments(arguments))
    }

    // MARK: - Private
}
