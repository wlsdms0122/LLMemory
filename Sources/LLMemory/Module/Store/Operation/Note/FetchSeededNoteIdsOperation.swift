//
//  FetchSeededNoteIdsOperation.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

// What the brain records as holding a copy some release planted. `update` needs
// it to see the ids a release has *stopped* shipping — walking the shipped list
// alone can only ever find what is still shipped.
struct FetchSeededNoteIdsOperation: GRDBReadOperation {
    // MARK: - Property
    typealias Parameter = Never
    // MARK: - Initializer
    // MARK: - Public
    func execute(_ db: Database) throws -> [String] {
        try String.fetchAll(db, sql: "SELECT id FROM notes WHERE seed = 1 ORDER BY id")
    }

    // MARK: - Private
}
