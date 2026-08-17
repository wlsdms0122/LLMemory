//
//  FetchNoteShapeOperation.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct FetchNoteShapeOperation: GRDBReadOperation {
    // MARK: - Property
    let nid: String

    // MARK: - Initializer
    init(nid: String) {
        self.nid = nid
    }

    // MARK: - Public
    func execute(_ db: Database) throws -> (words: Int, sections: Int) {
        let row = try Row.fetchOne(
            db,
            sql: "SELECT word_count, section_count FROM notes WHERE id = ?",
            arguments: [nid]
        )

        return (
            row?["word_count"] as Int? ?? 0,
            row?["section_count"] as Int? ?? 0
        )
    }

    // MARK: - Private
}
