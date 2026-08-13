//
//  ConsolidationTransactions.swift
//  LLMemory
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import GRDB

// Consolidation hygiene transactions — retention compaction, prune passes,
// integrity probes, and the tag report.
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
                sql: "SELECT title, summary FROM notes WHERE id = ?",
                arguments: [noteId]
            )
            
            guard let row else { continue }
            
            let title: String = row["title"]
            let summary: String? = row["summary"]
            let path = Paths.file(forId: noteId)
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
        let ids = try String.fetchAll(db, sql: "SELECT id FROM notes ORDER BY id")
        let issues = try ids.compactMap { id -> String? in
            let path = Paths.file(forId: id)
            let relative = Paths.relative(of: path) ?? path.path
            
            do {
                guard try Notes.readNoteIfPresent(at: path) != nil else {
                    return "missing: \(id) → \(relative)"
                }
                
                return nil
            } catch let error as NoteUnreadable {
                return "unreadable: \(id) → \(relative): \(error.reason)"
            }
        }
        
        return (ids.count, issues)
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
            .map { entry in TagCount(tag: entry.0, count: entry.1) }
        let unused = try String.fetchAll(db, sql: """
            SELECT tv.tag FROM tag_vocab tv
            LEFT JOIN tags t ON t.tag = tv.tag WHERE t.tag IS NULL
            ORDER BY tv.tag
            """)
        
        return ConsolidateTagReport(rare: Array(rare), unused: unused)
    }

    // MARK: - Private
}

