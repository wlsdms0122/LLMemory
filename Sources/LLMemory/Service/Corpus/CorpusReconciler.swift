//
//  CorpusReconciler.swift
//  LLMemory
//
//  Created by JSilver on 8/17/26.
//

import Foundation

// The two questions that compare the database against the files it projects.
//
// Both walk from an id the database gave to the file that id addresses, so
// neither is a transaction: the walk is the address grammar, and the store
// would have to know it to finish either answer.
struct CorpusReconciler {
    // MARK: - Property
    private let noteFile = NoteFile()

    // MARK: - Initializer
    // MARK: - Public
    // Every catalogued note still has a readable file behind it (L1).
    func checkFilesPresent(
        _ scope: GRDBReadScope,
        _ brain: BrainContext
    ) throws -> (checked: Int, issues: [String]) {
        let ids = try scope.run(FetchAllNoteIdsTransaction())
        let issues = try ids.compactMap { id -> String? in
            let file = brain.layout.file(forId: id)
            let relative = brain.layout.relativeFile(forId: id)

            do {
                guard try noteFile.readNoteIfPresent(at: file) != nil else {
                    return "missing: \(id) → \(relative)"
                }

                return nil
            } catch let error as NoteUnreadable {
                return "unreadable: \(id) → \(relative): \(error.reason)"
            }
        }

        return (ids.count, issues)
    }

    // The FTS shadow agrees with the catalog: rows for notes that are gone go
    // away, and notes with no row are re-projected from their files. A note
    // whose file cannot be read is reported rather than dropped — an empty
    // search result is not the way to learn a note became unreadable.
    func reconcileSearchIndex(
        _ scope: GRDBScope,
        _ brain: BrainContext
    ) throws -> (orphansPruned: Int, refilled: Int, unreadable: [String]) {
        let noteIds = Set(try scope.run(FetchAllNoteIdsTransaction()))
        let ftsIds = Set(try scope.run(FetchIndexedNoteIdsTransaction()))
        let orphans = ftsIds.subtracting(noteIds)

        for orphan in orphans {
            try scope.run(DropNoteFTSTransaction(noteId: orphan))
        }

        var refilled = 0
        var unreadable: [String] = []

        for noteId in noteIds.subtracting(ftsIds).sorted() {
            guard let header = try scope.run(FetchNoteHeaderTransaction(noteId: noteId)) else {
                continue
            }

            let body: String
            do {
                guard let read = try noteFile.readNoteIfPresent(
                    at: brain.layout.file(forId: noteId)
                ) else {
                    continue
                }

                body = read.body
            } catch let error as NoteUnreadable {
                unreadable.append("\(noteId): \(error)")
                continue
            }

            try scope.run(
                ReindexNoteFTSTransaction(
                    noteId: noteId,
                    title: header.title,
                    summary: header.summary ?? "",
                    body: body
                )
            )
            refilled += 1
        }

        return (orphans.count, refilled, unreadable.sorted())
    }

    // MARK: - Private
}
