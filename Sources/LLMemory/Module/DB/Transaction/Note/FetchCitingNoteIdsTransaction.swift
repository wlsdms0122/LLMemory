//
//  FetchCitingNoteIdsTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

// Who cites this id — whether or not the citation currently resolves.
struct FetchCitingNoteIdsTransaction: GRDBReadTransaction {
    // MARK: - Property
    let marker: String

    // MARK: - Initializer
    init(marker: String) {
        self.marker = marker
    }

    // MARK: - Public
    func perform(_ db: Database) throws -> [String] {
        try String.fetchAll(
            db,
            sql: "SELECT DISTINCT src FROM note_ref_markers WHERE marker = ? ORDER BY src",
            arguments: [marker]
        )
    }

    // MARK: - Private
}
