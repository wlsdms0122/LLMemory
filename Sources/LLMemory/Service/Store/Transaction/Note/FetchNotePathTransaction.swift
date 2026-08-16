//
//  FetchNotePathTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct FetchNotePathTransaction: GRDBBrainReadTransaction {
    // MARK: - Property
    let nid: String

    // MARK: - Initializer
    init(nid: String) {
        self.nid = nid
    }

    // MARK: - Public
    // Existence is the only thing the DB is asked — where the note lives is a
    // function of its id, so nil here means "no such note", never "no path".
    func perform(_ db: Database, _ brain: BrainContext) throws -> URL? {
        guard try NoteExistsTransaction(nid: nid).perform(db) else { return nil }

        return brain.layout.file(forId: nid)
    }

    // MARK: - Private
}
