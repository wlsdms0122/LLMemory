//
//  FetchNoteEntitySetOperation.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct FetchNoteEntitySetOperation: GRDBReadOperation {
    // MARK: - Property
    typealias Parameter = String
    let nid: String

    // MARK: - Initializer
    init(nid: String) {
        self.nid = nid
    }

    // MARK: - Public
    func execute(_ db: Database) throws -> Set<String> {
        Set(try String.fetchAll(
            db,
            sql: "SELECT entity FROM entity_index WHERE note_id = ?",
            arguments: [nid]
        ))
    }

    // MARK: - Private
}
