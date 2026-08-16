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
    private let context: BrainContext


    // MARK: - Initializer
    init(queue: any DatabaseWriter, context: BrainContext) {
        self.queue = queue
        self.context = context
    }

    // MARK: - Public
    public func seededNoteIds() throws -> [String] {
        try queue.read { database in
            try FetchSeededNoteIdsTransaction().perform(database)
        }
    }

    // The rows go under the commit; the file moves after it. Reversed, a failing
    // commit would leave the catalog holding a note whose file is in the trash,
    // and no rollback can bring a moved file back. This way the worst case is a
    // file at an address the catalog forgot — which the index build at the end of
    // this same bootstrap puts back.
    @discardableResult
    public func removeNote(
        id: String,
        file: URL,
        flagReason: String,
        trashReason: String,
        now: Int
    ) throws -> URL? {
        try queue.write { database in
            try RemoveNoteRowsTransaction(nid: id, flagReason: flagReason, now: now)
                .perform(database)
        }

        return try Trash(paths: context.paths).file(file, reason: trashReason, now: now)
    }

    // MARK: - Private
}
