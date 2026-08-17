//
//  FetchClusterMemberRowsOperation.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct FetchClusterMemberRowsOperation: GRDBReadOperation {
    // MARK: - Property
    let ids: [String]

    // MARK: - Initializer
    init(ids: [String]) {
        self.ids = ids
    }

    // MARK: - Public
    func execute(_ db: Database) throws -> [MetaRow] {
        let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ",")

        return try Row.fetchAll(
            db,
            sql: "SELECT id, title, summary FROM notes WHERE id IN (\(placeholders)) ORDER BY id",
            arguments: StatementArguments(ids)
        ).map { row in
            MetaRow(
                id: row["id"],
                title: row["title"],
                summary: row["summary"] as String?
            )
        }
    }

    // MARK: - Private
}
