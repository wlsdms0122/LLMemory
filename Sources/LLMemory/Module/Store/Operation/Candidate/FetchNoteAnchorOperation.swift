//
//  FetchNoteAnchorOperation.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

// One note's retrieval-facing header — the anchor row for neighbor scoring.
// Where its body lives is the caller's to work out: the id it asked with is
// the address, so answering it here would be the store deriving a location.
struct FetchNoteAnchorOperation: GRDBReadOperation {
    // MARK: - Property
    typealias Parameter = String
    let nid: String

    // MARK: - Initializer
    init(nid: String) {
        self.nid = nid
    }

    // MARK: - Public
    func execute(_ db: Database) throws -> String? {
        try String.fetchOne(db, sql: "SELECT title FROM notes WHERE id = ?", arguments: [nid])
    }

    // MARK: - Private
}
