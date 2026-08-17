//
//  NoteWriteBookkeeper.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

// The bookkeeping that follows a write — the lifecycle event that says what
// happened, and the links a new note starts life with. Separated from the
// write itself because every op does its own writing and all of them owe
// these.
struct NoteWriteBookkeeper {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Public
    func recordEdit(
        _ db: Database,
        nid: String,
        opLabel: String,
        now: Int
    ) throws {
        try db.run(RecordNoteLifecycleEventTransaction(nid: nid, kind: "edited", reason: opLabel, now: now))
    }
    
    func seedInitialLinks(_ db: Database, nid: String, tags: [String]) throws {
        try db.run(SeedInitialLinksTransaction(nid: nid, tags: tags))
    }
    
    // MARK: - Private
}
