//
//  FetchSurfaceMetaRowsOperation.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct FetchSurfaceMetaRowsOperation: GRDBReadOperation {
    // MARK: - Property
    typealias Parameter = Never

    // MARK: - Initializer
    init() { }

    // MARK: - Public
    func execute(_ db: Database) throws -> [MetaRow] {
        try Row.fetchAll(
            db,
            sql: "SELECT id, title, summary FROM notes WHERE \(Policy.all(Policy.surface(""), Policy.notEager("")))"
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
