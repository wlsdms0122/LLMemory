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
        try RecordNoteLifecycleEventOperation(nid: nid, kind: "edited", reason: opLabel, now: now).execute(db)
    }
    
    func seedInitialLinks(_ db: Database, nid: String, tags: [String]) throws {
        try SeedInitialLinksOperation(nid: nid, tags: tags).execute(db)
    }
    
    // MARK: - Private
}
