//
//  FetchFamilyGraphOperation.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct FetchFamilyGraphOperation: GRDBReadOperation {
    // MARK: - Property
    typealias Parameter = Never

    // MARK: - Initializer
    init() { }

    // MARK: - Public
    func execute(_ db: Database) throws -> (notes: [String], siblingLinks: [(src: String, dst: String)]) {
        let notes = try String.fetchAll(db, sql: "SELECT id FROM notes")
        let links = try Row.fetchAll(
            db,
            sql: "SELECT src, dst FROM note_links WHERE kind = ?",
            arguments: [LinkKind.sibling.rawValue]
        )
            .map { row in (src: row["src"] as String, dst: row["dst"] as String) }

        return (notes, links)
    }

    // MARK: - Private
}
