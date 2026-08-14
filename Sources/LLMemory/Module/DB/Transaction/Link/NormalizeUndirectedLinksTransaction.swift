//
//  NormalizeUndirectedLinksTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct NormalizeUndirectedLinksTransaction: GRDBTransaction {
    // MARK: - Property
    let nodeId: String

    // MARK: - Initializer
    init(nodeId: String) {
        self.nodeId = nodeId
    }

    // MARK: - Public
    func perform(_ db: Database) throws {
        let kinds = Array(Links.undirectedKinds)
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
