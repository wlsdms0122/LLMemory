//
//  ReparentNoteArtifactsTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct ReparentNoteArtifactsTransaction: GRDBTransaction {
    // MARK: - Property
    let from: String
    let to: String

    private let noteArtifacts = NoteArtifacts()

    // MARK: - Initializer
    init(from: String, to: String) {
        self.from = from
        self.to = to
    }

    // MARK: - Public
    func perform(_ db: Database) throws {
        guard self.from != to else { return }
        
        for table in NoteArtifacts.identityTables + NoteArtifacts.historyTables {
            try db.execute(sql: "DELETE FROM \(table) WHERE note_id = ?", arguments: [to])
            try db.execute(
                sql: "UPDATE \(table) SET note_id = ? WHERE note_id = ?",
                arguments: [to, self.from]
            )
        }
        
        try noteArtifacts.moveAuthoredLinks(db, from: self.from, to: to)
    }

    // MARK: - Private
}
