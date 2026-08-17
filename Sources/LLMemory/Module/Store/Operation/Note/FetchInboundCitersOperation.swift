//
//  FetchInboundCitersOperation.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

// Who cites this address. note_ref_markers records a citation whether or not
// it resolved, so re-addressing knows the set of notes to touch rather than
// searching the corpus for it.
struct FetchInboundCitersOperation: GRDBReadOperation {
    // MARK: - Property
    let marker: String
    let excluding: String

    // MARK: - Initializer
    init(marker: String, excluding: String) {
        self.marker = marker
        self.excluding = excluding
    }

    // MARK: - Public
    func execute(_ db: Database) throws -> [String] {
        try String.fetchAll(
            db,
            sql: "SELECT DISTINCT src FROM note_ref_markers WHERE marker = ? AND src != ?",
            arguments: [marker, excluding]
        )
            .sorted()
    }

    // MARK: - Private
}
