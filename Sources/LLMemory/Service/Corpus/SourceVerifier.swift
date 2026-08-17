//
//  SourceVerifier.swift
//  LLMemory
//
//  Created by JSilver on 8/17/26.
//

import Foundation
import GRDB

// Drift checking for the files a note was written from.
//
// It is not a transaction, because most of what it does is not one: the
// declared paths come out of the note's frontmatter, the fingerprints come
// off the source files themselves, and the database only holds the last
// answer. A transaction that opened those files to finish its work would be
// the store deciding where a note lives and what it declares.
struct SourceVerifier {
    // MARK: - Property
    private let noteFile = NoteFile()
    private let fingerprint = SourceFingerprint()

    // MARK: - Initializer
    // MARK: - Public
    // What the note declares as its sources, or nothing when the brain has no
    // such note. Throws NoteUnreadable for a note whose file cannot be parsed.
    func declaredPaths(
        _ db: Database,
        _ brain: BrainContext,
        noteId: String
    ) throws -> [String] {
        guard let file = try brain.notePath(db, noteId) else { return [] }

        return try noteFile.requireNote(at: file).doc.source
    }

    // Every tracked note, counted. A note whose file cannot be read is
    // reported rather than skipped — the corpus is the authority, so losing
    // access to it is the finding.
    func verifyAll(
        _ db: Database,
        _ brain: BrainContext,
        now: Int? = nil
    ) throws -> SourceVerifyResult {
        let timestamp = now ?? Int(Date().timeIntervalSince1970)
        let tracked = try db.run(FetchSourceTrackingTransaction())
        var result = SourceVerifyResult(
            total: tracked.count,
            rechecked: 0,
            stillFresh: 0,
            becameStale: 0,
            recovered: 0,
            missing: 0
        )

        for tracking in tracked {
            let noteId = tracking.noteId
            let declared: [String]
            do {
                declared = try declaredPaths(db, brain, noteId: noteId)
            } catch {
                guard error is NoteUnreadable else { throw error }

                result.unreadable.append("\(noteId): \(error)")
                continue
            }

            let checkable = declared.filter(fingerprint.isDriftCheckable)

            if checkable.isEmpty {
                try db.run(SetSourceStalenessTransaction(noteId: noteId, stale: nil))
                continue
            }

            if fingerprint.computeDeclHash(declared) != tracking.declHash {
                try db.run(
                    RebaseNoteSourceTransaction(noteId: noteId, paths: declared, now: timestamp)
                )
                result.rechecked += 1

                if tracking.stale { result.recovered += 1 }

                continue
            }

            let anyExists = checkable.contains { path in
                FileManager.default.fileExists(atPath: fingerprint.resolve(path).path)
            }
            let stale: Bool

            if anyExists {
                stale = fingerprint.computeFingerprint(checkable) != tracking.sourceHash

                if !stale { result.stillFresh += 1 }

                result.rechecked += 1
            } else {
                result.missing += 1
                stale = true
            }

            if stale, !tracking.stale {
                result.becameStale += 1
            } else if !stale, tracking.stale {
                result.recovered += 1
            }

            try db.run(SetSourceStalenessTransaction(noteId: noteId, stale: stale))
        }

        return result
    }

    // MARK: - Private
}
