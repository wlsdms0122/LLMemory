//
//  RemoveNoteRowsTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

// Everything a note's removal owes the catalog: whoever cited it is flagged
// before the row that anchors them goes, and every table keyed to the id goes
// with it. A person deleting a note and a release retiring a seed share this
// rather than each spelling out five steps.
//
// The file is not moved here. A transaction rolls back and a moved file does
// not, so a filesystem side effect inside one is a promise this type cannot
// keep — and hiding it behind the word Transaction is worse than leaving it in
// the open. Callers trash the file, where they can also see what compensates
// them if the commit does not land.
struct RemoveNoteRowsTransaction: GRDBTransaction {
    // MARK: - Property
    let nid: String
    // Why the citers are being flagged — what they will read when they look.
    let flagReason: String
    let now: Int

    // MARK: - Initializer
    init(nid: String, flagReason: String, now: Int) {
        self.nid = nid
        self.flagReason = flagReason
        self.now = now
    }

    // MARK: - Public
    func perform(_ db: Database) throws {
        // Flagged first: the referrers are read through the row that the deletes
        // below are about to take away.
        _ = try FlagInboundReferrersTransaction(
            targetId: nid,
            reason: flagReason,
            now: now
        ).perform(db)

        try DeleteNoteRowTransaction(nid: nid).perform(db)
        try DeleteNoteEntitiesTransaction(noteId: nid).perform(db)
        try DeleteNoteRippleFlagsTransaction(noteId: nid).perform(db)
    }

    // MARK: - Private
}
