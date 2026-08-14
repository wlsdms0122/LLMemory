//
//  VerifySourcesTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct VerifySourcesTransaction: GRDBTransaction {
    // MARK: - Property
    let now: Int?

    private let sourceFingerprint = SourceFingerprint()

    // MARK: - Initializer
    init(now: Int? = nil) {
        self.now = now
    }

    // MARK: - Public
    func perform(_ db: Database) throws -> SourceVerifyResult {
        let now = self.now ?? Int(Date().timeIntervalSince1970)
        let rows = try Row.fetchAll(db, sql: """
            SELECT note_id AS id, source_hash, source_stale, decl_hash FROM note_source
            WHERE source_hash IS NOT NULL
            """)
        var result = SourceVerifyResult(
            total: rows.count,
            rechecked: 0,
            stillFresh: 0,
            becameStale: 0,
            recovered: 0,
            missing: 0
        )

        for row in rows {
            let noteId: String = row["id"]
            let stored: String? = row["source_hash"]
            let previousStale: Int = row["source_stale"] as Int? ?? 0
            let storedDecl: String? = row["decl_hash"]
            let allPaths: [String]
            do {
                allPaths = try FetchNoteSourcePathsTransaction(noteId: noteId).perform(db)
            } catch {
                guard error is NoteUnreadable else { throw error }

                result.unreadable.append("\(noteId): \(error)")
                continue
            }

            let sourcePaths = allPaths.filter(sourceFingerprint.isDriftCheckable)

            if sourcePaths.isEmpty {
                try db.execute(
                    sql: "DELETE FROM note_source WHERE note_id = ?",
                    arguments: [noteId]
                )
                continue
            }

            if sourceFingerprint.computeDeclHash(allPaths) != storedDecl {
                try RebaseNoteSourceTransaction(noteId: noteId, paths: allPaths, now: now).perform(db)
                result.rechecked += 1

                if previousStale == 1 { result.recovered += 1 }

                continue
            }

            let anyExists = sourcePaths.contains { path in
                FileManager.default.fileExists(atPath: sourceFingerprint.resolve(path).path)
            }
            let newStale: Int

            if !anyExists {
                result.missing += 1
                newStale = 1
            } else {
                let current = sourceFingerprint.computeFingerprint(sourcePaths)
                newStale = (current == stored) ? 0 : 1

                if newStale == 0 { result.stillFresh += 1 }

                result.rechecked += 1
            }

            if newStale == 1 && previousStale == 0 {
                result.becameStale += 1
            } else if newStale == 0 && previousStale == 1 {
                result.recovered += 1
            }

            try db.execute(
                sql: "UPDATE note_source SET source_stale = ? WHERE note_id = ?",
                arguments: [newStale, noteId]
            )
        }

        return result
    }

    // MARK: - Private
}
