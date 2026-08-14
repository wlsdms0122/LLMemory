//
//  RemoveNoteTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

// Taking a note out of the corpus is more than moving its file. Whoever cited it
// has to be told, and the rows keyed to its id go with it — otherwise the note
// leaves quietly and its absence surfaces later as a dangling reference nobody
// was warned about.
//
// A person deleting a note and a release retiring a seed are two reasons for one
// sequence. They share it rather than each spelling it out, because a second copy
// of a five-step removal is a second chance to forget a step.
struct RemoveNoteTransaction: GRDBTransaction {
    // MARK: - Property
    let nid: String
    let file: URL
    // Why the citers are being flagged — what they will read when they look.
    let flagReason: String
    // Why the note left, recorded on the trashed copy itself.
    let trashReason: String
    let now: Int

    // MARK: - Initializer
    init(nid: String, file: URL, flagReason: String, trashReason: String, now: Int) {
        self.nid = nid
        self.file = file
        self.flagReason = flagReason
        self.trashReason = trashReason
        self.now = now
    }

    // MARK: - Public
    @discardableResult
    func perform(_ db: Database) throws -> URL? {
        // Flagged before the file moves: the referrers are read out of the
        // catalog, and the catalog is about to lose the row that anchors them.
        _ = try FlagInboundReferrersTransaction(
            targetId: nid,
            reason: flagReason,
            now: now
        ).perform(db)

        let trashPath = try Trash.file(file, reason: trashReason, now: now)

        try DeleteNoteRowTransaction(nid: nid).perform(db)
        try DeleteNoteEntitiesTransaction(noteId: nid).perform(db)
        try DeleteNoteRippleFlagsTransaction(noteId: nid).perform(db)

        return trashPath
    }

    // MARK: - Private
}
