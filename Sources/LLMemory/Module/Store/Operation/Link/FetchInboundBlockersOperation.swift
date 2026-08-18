//
//  FetchInboundBlockersOperation.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct FetchInboundBlockersOperation: GRDBReadOperation {
    // MARK: - Property
    typealias Parameter = (String, Int)
    let noteId: String
    let limit: Int

    // MARK: - Initializer
    init(noteId: String, limit: Int = 5) {
        self.noteId = noteId
        self.limit = limit
    }

    // MARK: - Public
    func execute(_ db: Database) throws -> [String] {
        let directed = LinkKind.rawValues { kind in kind.blocksDelete && !kind.isUndirected }
        let symmetric = LinkKind.rawValues { kind in kind.blocksDelete && kind.isUndirected }
        let directedPlaceholders = directed.map { _ in "?" }.joined(separator: ",")
        let symmetricPlaceholders = symmetric.map { _ in "?" }.joined(separator: ",")
        var arguments: [DatabaseValueConvertible?] = [noteId]
        arguments.append(contentsOf: directed as [DatabaseValueConvertible?])
        arguments.append(contentsOf: [noteId, noteId, noteId] as [DatabaseValueConvertible?])
        arguments.append(contentsOf: symmetric as [DatabaseValueConvertible?])
        arguments.append(limit)

        return try String.fetchAll(db, sql: """
            SELECT other FROM (
              SELECT src AS other FROM note_links WHERE dst = ? AND kind IN (\(directedPlaceholders))
              UNION
              SELECT CASE WHEN src = ? THEN dst ELSE src END AS other FROM note_links
              WHERE (src = ? OR dst = ?) AND kind IN (\(symmetricPlaceholders))
            ) ORDER BY other LIMIT ?
            """, arguments: StatementArguments(arguments))
    }

    // MARK: - Private
}
