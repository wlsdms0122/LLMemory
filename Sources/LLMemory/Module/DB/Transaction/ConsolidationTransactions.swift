//
//  ConsolidationTransactions.swift
//  LLMemory
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import GRDB

// Consolidation hygiene transactions — retention compaction, prune passes,
// integrity probes, and the axis/tag reports.
struct CompactOldEventsTransaction: GRDBTransaction {
    // MARK: - Property
    let now: Int
    let retentionSec: Int

    // MARK: - Initializer
    init(now: Int, retentionSec: Int) {
        self.now = now
        self.retentionSec = retentionSec
    }

    // MARK: - Public
    func perform(_ db: Database) throws -> (compacted: Int, days: Int) {
        let cutoff = now - retentionSec
        
        try db.execute(sql: "DELETE FROM events WHERE ts < ?", arguments: [cutoff])
        
        return (db.changesCount, 0)
    }

    // MARK: - Private
}

struct PruneResolvedRippleFlagsTransaction: GRDBTransaction {
    // MARK: - Property
    let now: Int
    let retentionDays: Int

    // MARK: - Initializer
    init(now: Int, retentionDays: Int = 30) {
        self.now = now
        self.retentionDays = retentionDays
    }

    // MARK: - Public
    func perform(_ db: Database) throws -> Int {
        let cutoff = now - retentionDays * 86400
        
        try db.execute(
            sql: "DELETE FROM ripple_flags WHERE resolved_at IS NOT NULL AND resolved_at < ?",
            arguments: [cutoff]
        )
        
        return db.changesCount
    }

    // MARK: - Private
}

struct PruneOldLifecycleEventsTransaction: GRDBTransaction {
    // MARK: - Property
    let now: Int
    let retentionDays: Int

    // MARK: - Initializer
    init(now: Int, retentionDays: Int = 180) {
        self.now = now
        self.retentionDays = retentionDays
    }

    // MARK: - Public
    func perform(_ db: Database) throws -> Int {
        let cutoff = now - retentionDays * 86400
        
        try db.execute(
            sql: "DELETE FROM note_lifecycle_events WHERE created_at < ?",
            arguments: [cutoff]
        )
        
        return db.changesCount
    }

    // MARK: - Private
}

struct PruneFtsOrphansTransaction: GRDBTransaction {
    // MARK: - Initializer
    init() { }

    // MARK: - Public
    func perform(_ db: Database) throws -> (orphansPruned: Int, refilled: Int, unreadable: [String]) {
        let noteIds = Set(try String.fetchAll(db, sql: "SELECT id FROM notes"))
        let ftsIds = Set(try String.fetchAll(db, sql: "SELECT DISTINCT id FROM notes_fts"))
        let orphans = ftsIds.subtracting(noteIds)
        
        for orphanId in orphans {
            try db.execute(sql: "DELETE FROM notes_fts WHERE id = ?", arguments: [orphanId])
        }
        
        let missing = noteIds.subtracting(ftsIds)
        var refilled = 0
        var unreadable: [String] = []
        
        for noteId in missing {
            let row = try Row.fetchOne(
                db,
                sql: "SELECT path, title, summary FROM notes WHERE id = ?",
                arguments: [noteId]
            )
            
            guard let row else { continue }
            
            let relativePath: String = row["path"]
            let title: String = row["title"]
            let summary: String? = row["summary"]
            let path = Paths.brainRoot.appendingPathComponent(relativePath)
            let body: String
            do {
                guard let read = try Notes.readNoteIfPresent(at: path) else { continue }
                
                body = read.body
            } catch let error as NoteUnreadable {
                unreadable.append("\(noteId): \(error)")
                continue
            }
            
            try ReindexNoteFTSTransaction(noteId: noteId,
                title: title,
                summary: summary ?? "",
                body: body
            ).perform(db)
            refilled += 1
        }
        
        return (orphans.count, refilled, unreadable.sorted())
    }

    // MARK: - Private
}

struct CheckCorpusIntegrityL1Transaction: GRDBReadTransaction {
    // MARK: - Initializer
    init() { }

    // MARK: - Public
    func perform(_ db: Database) throws -> (checked: Int, issues: [String]) {
        let rows = try FetchAllNotePathsTransaction().perform(db)
        let issues = try rows.compactMap { row -> String? in
            let path = Paths.brainRoot.appendingPathComponent(row.path)
            
            do {
                guard try Notes.readNoteIfPresent(at: path) != nil else {
                    return "missing: \(row.id) → \(row.path)"
                }
                
                return nil
            } catch let error as NoteUnreadable {
                return "unreadable: \(row.id) → \(row.path): \(error.reason)"
            }
        }
        
        return (rows.count, issues)
    }

    // MARK: - Private
}

struct FetchAxisReportTransaction: GRDBReadTransaction {
    // MARK: - Property
    let low: Int
    let high: Int

    // MARK: - Initializer
    init(low: Int = 2, high: Int = 20) {
        self.low = low
        self.high = high
    }

    // MARK: - Public
    func perform(_ db: Database) throws -> ConsolidateAxisReport {
        let rows = try Row.fetchAll(db, sql: """
            SELECT a.axis, a.description, COALESCE(COUNT(n.id), 0) AS c
            FROM axes a LEFT JOIN notes n ON n.axis = a.axis
            GROUP BY a.axis ORDER BY c ASC, a.axis
            """)
        let all: [(String, String?, Int)] = rows.map { row in
            (row["axis"] as String, row["description"] as String?, row["c"] as Int)
        }
        let small = all
            .filter { entry in entry.2 <= low }
            .map { entry in (axis: entry.0, count: entry.2) }
        let large = all
            .filter { entry in entry.2 >= high }
            .map { entry in (axis: entry.0, count: entry.2) }
        
        return ConsolidateAxisReport(
            all: all.map { entry in (axis: entry.0, description: entry.1, count: entry.2) },
            small: small,
            large: large
        )
    }

    // MARK: - Private
}

struct FetchTagReportTransaction: GRDBReadTransaction {
    // MARK: - Property
    let lowFreq: Int
    let limit: Int

    // MARK: - Initializer
    init(lowFreq: Int = 1, limit: Int = 40) {
        self.lowFreq = lowFreq
        self.limit = limit
    }

    // MARK: - Public
    func perform(_ db: Database) throws -> ConsolidateTagReport {
        let rows = try Row.fetchAll(
            db,
            sql: "SELECT tag, COUNT(*) c FROM tags GROUP BY tag ORDER BY c ASC, tag"
        )
        let all: [(String, Int)] = rows.map { row in (row["tag"] as String, row["c"] as Int) }
        let rare = all
            .filter { entry in entry.1 <= lowFreq }
            .prefix(limit)
            .map { entry in (tag: entry.0, count: entry.1) }
        let unused = try String.fetchAll(db, sql: """
            SELECT tv.tag FROM tag_vocab tv
            LEFT JOIN tags t ON t.tag = tv.tag WHERE t.tag IS NULL
            ORDER BY tv.tag
            """)
        
        return ConsolidateTagReport(rare: Array(rare), unused: unused)
    }

    // MARK: - Private
}

struct MarkConsolidatedTransaction: GRDBTransaction {
    // MARK: - Property
    let now: Int

    // MARK: - Initializer
    init(now: Int) {
        self.now = now
    }

    // MARK: - Public
    func perform(_ db: Database) throws {
        let count = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM notes") ?? 0
        
        for (key, value) in [
            ("last_consolidation_at", String(now)),
            ("last_consolidation_note_count", String(count))
        ] {
            try db.execute(sql: """
                INSERT INTO meta (key, value) VALUES (?, ?)
                ON CONFLICT(key) DO UPDATE SET value = excluded.value
                """, arguments: [key, value])
        }
    }

    // MARK: - Private
}
