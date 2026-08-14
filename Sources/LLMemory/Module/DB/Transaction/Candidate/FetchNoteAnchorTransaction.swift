//
//  FetchNoteAnchorTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

// One note's retrieval-facing header — the anchor row for neighbor scoring.
struct FetchNoteAnchorTransaction: GRDBReadTransaction {
    // MARK: - Property
    let nid: String

    // MARK: - Initializer
    init(nid: String) {
        self.nid = nid
    }

    // MARK: - Public
    func perform(_ db: Database) throws -> (title: String, path: URL)? {
        guard let title = try String.fetchOne(
            db,
            sql: "SELECT title FROM notes WHERE id = ?",
            arguments: [nid]
        ) else {
            return nil
        }

        return (title: title, path: Paths.file(forId: nid))
    }

    // MARK: - Private
}
