//
//  NormalizeUndirectedLinksOperation.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct NormalizeUndirectedLinksOperation: GRDBOperation {
    // MARK: - Property
    typealias Parameter = String
    let nodeId: String

    // MARK: - Initializer
    init(nodeId: String) {
        self.nodeId = nodeId
    }

    // MARK: - Public
    func execute(_ db: Database) throws {
        let kinds = LinkKind.rawValues { kind in kind.isUndirected }
        let placeholders = kinds.map { _ in "?" }.joined(separator: ", ")
        let swapArguments = StatementArguments(kinds + [nodeId, nodeId])

        try db.execute(
            sql: "UPDATE OR IGNORE note_links SET src = dst, dst = src WHERE kind IN (\(placeholders)) AND src > dst AND (src = ? OR dst = ?)",
            arguments: swapArguments
        )
        try db.execute(
            sql: "DELETE FROM note_links WHERE kind IN (\(placeholders)) AND src > dst AND (src = ? OR dst = ?)",
            arguments: swapArguments
        )
    }

    // MARK: - Private
}
