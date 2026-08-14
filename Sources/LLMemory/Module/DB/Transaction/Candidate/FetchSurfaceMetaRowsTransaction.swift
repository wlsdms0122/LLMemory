//
//  FetchSurfaceMetaRowsTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct FetchSurfaceMetaRowsTransaction: GRDBReadTransaction {
    private let policy = Policy()

    // MARK: - Initializer
    init() { }

    // MARK: - Public
    func perform(_ db: Database) throws -> [MetaRow] {
        try Row.fetchAll(
            db,
            sql: "SELECT id, title, summary FROM notes WHERE \(policy.all(policy.surface(""), policy.notEager("")))"
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
