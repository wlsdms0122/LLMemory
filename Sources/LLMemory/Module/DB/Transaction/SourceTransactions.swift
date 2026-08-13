//
//  SourceTransactions.swift
//  LLMemory
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import GRDB

// note_source transactions — projection, rebase, and drift verification of
// a note's declared source files. Hashing mechanics live in
// SourceFingerprint; these own the rows.
public struct SourceVerifyResult: Sendable {
    // MARK: - Property
    public var total: Int
    public var rechecked: Int
    public var stillFresh: Int
    public var becameStale: Int
    public var recovered: Int
    public var missing: Int
    public var unreadable: [String] = []

    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}

struct FetchNoteSourcePathsTransaction: GRDBReadTransaction {
    // MARK: - Property
    let noteId: String

    // MARK: - Initializer
    init(noteId: String) {
        self.noteId = noteId
    }

    // MARK: - Public
    func perform(_ db: Database) throws -> [String] {
        guard try Int.fetchOne(
            db,
            sql: "SELECT 1 FROM notes WHERE id = ?",
            arguments: [noteId]
        ) != nil else {
            return []
        }

        return try Notes.requireNote(at: Paths.file(forId: noteId)).doc.source
    }

    // MARK: - Private
}

struct ProjectNoteRefsTransaction: GRDBTransaction {
    // MARK: - Property
    let noteId: String
    let paths: [String]
    let now: Int

    // MARK: - Initializer
    init(noteId: String, paths: [String], now: Int) {
        self.noteId = noteId
        self.paths = paths
        self.now = now
    }

    // MARK: - Public
    func perform(_ db: Database) throws {
        guard let fingerprint = SourceFingerprint.computeFingerprint(paths),
            let declHash = SourceFingerprint.computeDeclHash(paths)
        else {
            try db.execute(
                sql: "DELETE FROM note_source WHERE note_id = ?",
                arguments: [noteId]
            )

            return
        }

        let stored = try String.fetchOne(
            db,
            sql: "SELECT decl_hash FROM note_source WHERE note_id = ?",
            arguments: [noteId]
        )

        if stored == declHash { return }

        try RebaseNoteSourceTransaction(
            noteId: noteId,
            paths: paths,
            now: now,
            fingerprint: fingerprint,
            declHash: declHash
        )
            .perform(db)
    }

    // MARK: - Private
}

struct RebaseNoteSourceTransaction: GRDBTransaction {
    // MARK: - Property
    let noteId: String
    let paths: [String]
    let now: Int
    let fingerprint: String?
    let declHash: String?

    // MARK: - Initializer
    init(
        noteId: String,
        paths: [String],
        now: Int,
        fingerprint: String? = nil,
        declHash: String? = nil
    ) {
        self.noteId = noteId
        self.paths = paths
        self.now = now
        self.fingerprint = fingerprint
        self.declHash = declHash
    }

    // MARK: - Public
    func perform(_ db: Database) throws {
        guard let fingerprint = fingerprint ?? SourceFingerprint.computeFingerprint(paths),
            let declHash = declHash ?? SourceFingerprint.computeDeclHash(paths)
        else {
            try db.execute(
                sql: "DELETE FROM note_source WHERE note_id = ?",
                arguments: [noteId]
            )

            return
        }

        try db.execute(sql: """
            INSERT INTO note_source (note_id, source_hash, source_stale, decl_hash)
            VALUES (?, ?, 0, ?)
            ON CONFLICT(note_id) DO UPDATE SET
              source_hash = excluded.source_hash,
              source_stale = 0, decl_hash = excluded.decl_hash
            """, arguments: [noteId, fingerprint, declHash])
    }

    // MARK: - Private
}

struct InheritSourceObservationTransaction: GRDBTransaction {
    // MARK: - Property
    let from: String
    let to: String

    // MARK: - Initializer
    init(from: String, to: String) {
        self.from = from
        self.to = to
    }

    // MARK: - Public
    func perform(_ db: Database) throws {
        try db.execute(sql: """
            INSERT OR REPLACE INTO note_source (note_id, source_hash, source_stale, decl_hash)
            SELECT c.note_id, p.source_hash, p.source_stale, p.decl_hash
            FROM note_source p JOIN note_source c
              ON c.note_id = ? AND p.note_id = ? AND p.decl_hash = c.decl_hash
            """, arguments: [to, from])
    }

    // MARK: - Private
}

struct VerifyNoteSourceTransaction: GRDBTransaction {
    // MARK: - Property
    let noteId: String
    let now: Int?

    // MARK: - Initializer
    init(noteId: String, now: Int? = nil) {
        self.noteId = noteId
        self.now = now
    }

    // MARK: - Public
    @discardableResult
    func perform(_ db: Database) throws -> Bool {
        let timestamp = now ?? Int(Date().timeIntervalSince1970)
        let row = try Row.fetchOne(
            db,
            sql: "SELECT source_hash, decl_hash FROM note_source WHERE note_id = ?",
            arguments: [noteId]
        )

        guard let row, let stored = row["source_hash"] as String?, !stored.isEmpty else {
            return false
        }

        let paths = try FetchNoteSourcePathsTransaction(noteId: noteId).perform(db)

        guard let currentDecl = SourceFingerprint.computeDeclHash(paths),
            let current = SourceFingerprint.computeFingerprint(paths)
        else {
            try db.execute(
                sql: "DELETE FROM note_source WHERE note_id = ?",
                arguments: [noteId]
            )

            return false
        }

        if currentDecl != (row["decl_hash"] as String?) {
            try RebaseNoteSourceTransaction(
                noteId: noteId,
                paths: paths,
                now: timestamp,
                fingerprint: current,
                declHash: currentDecl
            )
                .perform(db)

            return false
        }

        let stale = current != stored

        try db.execute(
            sql: "UPDATE note_source SET source_stale = ? WHERE note_id = ?",
            arguments: [stale ? 1 : 0, noteId]
        )

        return stale
    }

    // MARK: - Private
}

struct FetchStaleSourceNoteIdsTransaction: GRDBReadTransaction {
    // MARK: - Initializer
    init() { }

    // MARK: - Public
    func perform(_ db: Database) throws -> Set<String> {
        Set(try String.fetchAll(db, sql: "SELECT note_id FROM note_source WHERE source_stale = 1"))
    }

    // MARK: - Private
}

struct VerifySourcesTransaction: GRDBTransaction {
    // MARK: - Property
    let now: Int?

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

            let sourcePaths = allPaths.filter(SourceFingerprint.isDriftCheckable)

            if sourcePaths.isEmpty {
                try db.execute(
                    sql: "DELETE FROM note_source WHERE note_id = ?",
                    arguments: [noteId]
                )
                continue
            }

            if SourceFingerprint.computeDeclHash(allPaths) != storedDecl {
                try RebaseNoteSourceTransaction(noteId: noteId, paths: allPaths, now: now).perform(db)
                result.rechecked += 1

                if previousStale == 1 { result.recovered += 1 }

                continue
            }

            let anyExists = sourcePaths.contains { path in
                FileManager.default.fileExists(atPath: SourceFingerprint.resolve(path).path)
            }
            let newStale: Int

            if !anyExists {
                result.missing += 1
                newStale = 1
            } else {
                let current = SourceFingerprint.computeFingerprint(sourcePaths)
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

