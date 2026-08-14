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
    // GRDB runs read/write bodies on its own serial queue, and a task-local does
    // not cross that thread. Everything below rebinds for the same reason every
    // GRDBStorage entry point does — without it a body resolves paths through the
    // process fallback, which is the most recently created live brain and not
    // necessarily this one.
    private let context: BrainContext

    private let trash = Trash()

    // MARK: - Initializer
    init(queue: any DatabaseWriter, context: BrainContext) {
        self.queue = queue
        self.context = context
    }

    // MARK: - Public
    public func seededNoteIds() throws -> [String] {
        try queue.read { database in
            try self.context.bind { try FetchSeededNoteIdsTransaction().perform(database) }
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
            try self.context.bind {
                try RemoveNoteRowsTransaction(nid: id, flagReason: flagReason, now: now)
                    .perform(database)
            }
        }

        return try trash.file(file, reason: trashReason, now: now)
    }

    // MARK: - Private
}
