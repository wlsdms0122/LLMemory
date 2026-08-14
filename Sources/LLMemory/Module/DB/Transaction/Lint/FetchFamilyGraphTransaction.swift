//
//  FetchFamilyGraphTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct FetchFamilyGraphTransaction: GRDBReadTransaction {
    // MARK: - Initializer
    init() { }

    // MARK: - Public
    func perform(_ db: Database) throws -> (notes: [String], siblingLinks: [(src: String, dst: String)]) {
        let notes = try String.fetchAll(db, sql: "SELECT id FROM notes")
        let links = try Row.fetchAll(
            db,
            sql: "SELECT src, dst FROM note_links WHERE kind = ?",
            arguments: [Links.kindSibling]
        )
            .map { row in (src: row["src"] as String, dst: row["dst"] as String) }

        return (notes, links)
    }

    // MARK: - Private
}
