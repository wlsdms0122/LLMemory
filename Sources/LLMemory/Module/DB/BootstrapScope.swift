//
//  BootstrapScope.swift
//  LLMemory
//
//  Created by JSilver on 8/14/26.
//

import Foundation
import GRDB

// The one window where init/update touch the corpus: after the migration, before
// the index is rebuilt. It hands the tiers above the two things seeding needs —
// what the brain already recorded, and the way a note leaves — without the
// connection itself crossing the Module boundary.
public struct BootstrapScope {
    // MARK: - Property
    private let queue: any DatabaseWriter

    // MARK: - Initializer
    init(queue: any DatabaseWriter) {
        self.queue = queue
    }

    // MARK: - Public
    public func seededNoteIds() throws -> [String] {
        try queue.read { database in try FetchSeededNoteIdsTransaction().perform(database) }
    }

    @discardableResult
    public func removeNote(
        id: String,
        file: URL,
        flagReason: String,
        trashReason: String,
        now: Int
    ) throws -> URL? {
        try queue.write { database in
            try RemoveNoteTransaction(
                nid: id,
                file: file,
                flagReason: flagReason,
                trashReason: trashReason,
                now: now
            ).perform(database)
        }
    }

    // MARK: - Private
}
