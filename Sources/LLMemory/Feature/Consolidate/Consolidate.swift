//
//  Consolidate.swift
//  LLMemory
//
//  Created by JSilver on 8/7/26.
//

import Foundation
import GRDB

public enum Consolidate {
    public struct AxisReport {
        // MARK: - Property
        public let all: [(axis: String, description: String?, count: Int)]
        public let small: [(axis: String, count: Int)]
        public let large: [(axis: String, count: Int)]
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    public struct TagReport {
        // MARK: - Property
        public let rare: [(tag: String, count: Int)]
        public let unused: [String]
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    public struct IntegrateResult: Encodable {
        public enum CodingKeys: String, CodingKey {
            case summary
            case axisReport = "axis_report"
            case tagReport = "tag_report"
            case prune
            case integrityL1 = "integrity_l1"
        }
        
        public struct Summary: Encodable {
            public enum CodingKeys: String, CodingKey {
                case eventsCompacted = "events_compacted"
                case smallAxes = "small_axes"
                case largeAxes = "large_axes"
                case rareTags = "rare_tags"
                case unusedVocabTags = "unused_vocab_tags"
                case emptyAxesPruned = "empty_axes_pruned"
                case unusedVocabPruned = "unused_vocab_pruned"
                case resolvedRipplePruned = "resolved_ripple_pruned"
                case ftsOrphansPruned = "fts_orphans_pruned"
                case ftsRefilled = "fts_refilled"
                case integrityL1Issues = "integrity_l1_issues"
                case linksDecayed = "links_decayed"
                case linksPruned = "links_pruned"
                case sourcesRechecked = "sources_rechecked"
                case sourcesBecameStale = "sources_became_stale"
                case sourcesRecovered = "sources_recovered"
                case sourcesMissing = "sources_missing"
                case sourcesUnreadable = "sources_unreadable"
                case termsActivated = "terms_activated"
                case termsRejected = "terms_rejected"
                case enrichReviewFlagged = "enrich_review_flagged"
                case enrichReviewResolved = "enrich_review_resolved"
                case vectorsBuilt = "vectors_built"
            }
            
            // MARK: - Property
            public let eventsCompacted: Int
            public let smallAxes: Int
            public let largeAxes: Int
            public let rareTags: Int
            public let unusedVocabTags: Int
            public let emptyAxesPruned: Int
            public let unusedVocabPruned: Int
            public let resolvedRipplePruned: Int
            public let ftsOrphansPruned: Int
            public let ftsRefilled: Int
            public var integrityL1Issues: Int
            public let linksDecayed: Int
            public let linksPruned: Int
            public let sourcesRechecked: Int
            public let sourcesBecameStale: Int
            public let sourcesRecovered: Int
            public let sourcesMissing: Int
            public let sourcesUnreadable: Int
            public let termsActivated: Int
            public let termsRejected: Int
            public let enrichReviewFlagged: Int
            public let enrichReviewResolved: Int
            public let vectorsBuilt: Int
            
            // MARK: - Initializer
            // MARK: - Public
            // MARK: - Private
        }
        
        public struct AxisReportOutput: Encodable {
            // MARK: - Property
            public let all: [AxisRow]
            public let small: [AxisCount]
            public let large: [AxisCount]
            
            // MARK: - Initializer
            // MARK: - Public
            // MARK: - Private
        }
        
        public struct AxisRow: Encodable {
            // MARK: - Property
            public let axis: String
            public let description: String?
            public let count: Int
            
            // MARK: - Initializer
            // MARK: - Public
            public func encode(to encoder: Encoder) throws {
                var container = encoder.unkeyedContainer()
                
                try container.encode(axis)
                
                if let description {
                    try container.encode(description)
                } else {
                    try container.encodeNil()
                }
                
                try container.encode(count)
            }
            
            // MARK: - Private
        }
        
        public struct AxisCount: Encodable {
            // MARK: - Property
            public let axis: String
            public let count: Int
            
            // MARK: - Initializer
            // MARK: - Public
            public func encode(to encoder: Encoder) throws {
                var container = encoder.unkeyedContainer()
                
                try container.encode(axis)
                try container.encode(count)
            }
            
            // MARK: - Private
        }
        
        public struct TagReportOutput: Encodable {
            // MARK: - Property
            public let rare: [TagCount]
            public let unused: [String]
            
            // MARK: - Initializer
            // MARK: - Public
            // MARK: - Private
        }
        
        public struct TagCount: Encodable {
            // MARK: - Property
            public let tag: String
            public let count: Int
            
            // MARK: - Initializer
            // MARK: - Public
            public func encode(to encoder: Encoder) throws {
                var container = encoder.unkeyedContainer()
                
                try container.encode(tag)
                try container.encode(count)
            }
            
            // MARK: - Private
        }
        
        public struct PruneReport: Encodable {
            public enum CodingKeys: String, CodingKey {
                case axes
                case tagVocab = "tag_vocab"
            }
            
            public struct GroupReport: Encodable {
                // MARK: - Property
                public let pruned: [String]
                public let count: Int
                
                // MARK: - Initializer
                // MARK: - Public
                // MARK: - Private
            }
            
            // MARK: - Property
            public let axes: GroupReport
            public let tagVocab: GroupReport
            
            // MARK: - Initializer
            // MARK: - Public
            // MARK: - Private
        }
        
        public struct IntegrityReport: Encodable {
            // MARK: - Property
            public let checked: Int
            public let issues: [String]
            
            // MARK: - Initializer
            // MARK: - Public
            // MARK: - Private
        }
        
        // MARK: - Property
        public var summary: Summary
        public let axisReport: AxisReportOutput
        public let tagReport: TagReportOutput
        public let prune: PruneReport
        public var integrityL1: IntegrityReport
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    public struct PruneResult: Encodable {
        public enum CodingKeys: String, CodingKey {
            case linksDecayed = "links_decayed"
            case linksPruned = "links_pruned"
        }
        
        // MARK: - Property
        public let linksDecayed: Int
        public let linksPruned: Int
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    // MARK: - Property
    private static var retentionSec: Int {
        Config.getInt("events.retention_days", default: 30) * 24 * 60 * 60
    }
    
    // MARK: - Initializer
    // MARK: - Public
    public static func compactOldEvents(
        _ db: Database,
        now: Int,
        retentionSec: Int
    ) throws -> (compacted: Int, days: Int) {
        let cutoff = now - retentionSec
        
        try db.execute(sql: "DELETE FROM events WHERE ts < ?", arguments: [cutoff])
        
        return (db.changesCount, 0)
    }
    
    public static func pruneEmptyAxes(_ db: Database) throws -> (pruned: [String], count: Int) {
        let pruned = try Vocab.pruneEmptyAxes(db)
        
        return (pruned, pruned.count)
    }
    
    public static func pruneUnusedVocabTags(
        _ db: Database
    ) throws -> (pruned: [String], count: Int) {
        let pruned = try Vocab.pruneUnusedVocabTags(db)
        
        return (pruned, pruned.count)
    }
    
    public static func pruneResolvedRippleFlags(
        _ db: Database,
        now: Int,
        retentionDays: Int = 30
    ) throws -> Int {
        let cutoff = now - retentionDays * 86400
        
        try db.execute(
            sql: "DELETE FROM ripple_flags WHERE resolved_at IS NOT NULL AND resolved_at < ?",
            arguments: [cutoff]
        )
        
        return db.changesCount
    }
    
    public static func pruneOldLifecycleEvents(
        _ db: Database,
        now: Int,
        retentionDays: Int = 180
    ) throws -> Int {
        let cutoff = now - retentionDays * 86400
        
        try db.execute(
            sql: "DELETE FROM note_lifecycle_events WHERE created_at < ?",
            arguments: [cutoff]
        )
        
        return db.changesCount
    }
    
    public static func pruneFtsOrphans(
        _ db: Database
    ) throws -> (orphansPruned: Int, refilled: Int, unreadable: [String]) {
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
            
            try Notes.reindexFTS(
                db,
                noteId: noteId,
                title: title,
                summary: summary ?? "",
                body: body
            )
            refilled += 1
        }
        
        return (orphans.count, refilled, unreadable.sorted())
    }
    
    public static func integrityL1(_ db: Database) throws -> (checked: Int, issues: [String]) {
        let rows = try Notes.allPathsRel(db)
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
    
    public static func axisReport(_ db: Database, low: Int = 2, high: Int = 20) throws -> AxisReport {
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
        
        return AxisReport(
            all: all.map { entry in (axis: entry.0, description: entry.1, count: entry.2) },
            small: small,
            large: large
        )
    }
    
    public static func tagReport(
        _ db: Database,
        lowFreq: Int = 1,
        limit: Int = 40
    ) throws -> TagReport {
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
        
        return TagReport(rare: Array(rare), unused: unused)
    }
    
    public static func report() throws -> (axis: AxisReport, tag: TagReport) {
        let queue = try DB.connect()
        let axisSummary = try queue.read { db in try axisReport(db) }
        let tagSummary = try queue.read { db in try tagReport(db) }
        
        return (axisSummary, tagSummary)
    }
    
    public static func markConsolidated(_ db: Database, now: Int) throws {
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
    
    public static func integrate() throws -> IntegrateResult {
        var result = try DB.writeLock { try integrateLocked() }
        let integrity = try DB.connect().read { db in try integrityL1(db) }
        result.integrityL1 = IntegrateResult.IntegrityReport(
            checked: integrity.checked,
            issues: integrity.issues
        )
        result.summary.integrityL1Issues = integrity.issues.count
        
        return result
    }
    
    public static func homeostasis() throws -> Homeostasis.Report {
        try DB.writeLock {
            let now = Int(Date().timeIntervalSince1970)
            var report: Homeostasis.Report!
            
            try DB.write { db in
                _ = try Activation.deriveWindows(db, now: now)
                report = try Homeostasis.tick(db, now: now)
            }
            
            Events.record(
                kind: Events.kindConsolidation,
                payload: [
                    "action": "homeostasis",
                    "windows_processed": report.windowsProcessed,
                    "adjusted_gene": report.adjustedGene as Any?,
                    "note": report.note
                ],
                ts: now
            )
            
            return report
        }
    }
    
    public static func prune() throws -> PruneResult {
        try DB.writeLock {
            let now = Int(Date().timeIntervalSince1970)
            var decay: (decayed: Int, pruned: Int) = (0, 0)
            
            try DB.write { db in
                decay = try Links.decayAndPrune(db)
            }
            
            Events.record(
                kind: Events.kindConsolidation,
                payload: [
                    "action": "prune",
                    "links_decayed": decay.decayed,
                    "links_pruned": decay.pruned
                ],
                ts: now
            )
            
            return PruneResult(linksDecayed: decay.decayed, linksPruned: decay.pruned)
        }
    }
    
    // MARK: - Private
    private static func integrateLocked() throws -> IntegrateResult {
        let now = Int(Date().timeIntervalSince1970)
        var axisSummary: AxisReport!
        var tagSummary: TagReport!
        var eventsCompacted = 0
        var sourceVerify = SourcesService.BulkVerifyResult(
            total: 0,
            rechecked: 0,
            stillFresh: 0,
            becameStale: 0,
            recovered: 0,
            missing: 0
        )
        var prunedAxes: [String] = []
        var prunedAxesCount = 0
        var prunedTags: [String] = []
        var prunedTagsCount = 0
        var prunedRippleFlags = 0
        var ftsPrune: (orphansPruned: Int, refilled: Int, unreadable: [String]) = (0, 0, [])
        var termsActivated = 0
        var termsRejected = 0
        var reviewPass = EnrichmentReview.ReviewPass()
        
        try DB.write { db in
            _ = try Activation.deriveWindows(db, now: now)
            
            eventsCompacted = try compactOldEvents(
                db,
                now: now,
                retentionSec: retentionSec
            ).compacted
            axisSummary = try axisReport(db)
            tagSummary = try tagReport(db)
            sourceVerify = try SourcesService.bulkVerify(db, now: now)
            
            let axisPrune = try pruneEmptyAxes(db)
            let tagPrune = try pruneUnusedVocabTags(db)
            prunedRippleFlags = try pruneResolvedRippleFlags(db, now: now)
            
            _ = try pruneOldLifecycleEvents(
                db,
                now: now,
                retentionDays: Config.getInt("lifecycle.retention_days", default: 180)
            )
            
            ftsPrune = try pruneFtsOrphans(db)
            prunedAxes = axisPrune.pruned
            prunedAxesCount = axisPrune.count
            prunedTags = tagPrune.pruned
            prunedTagsCount = tagPrune.count
            
            let validationPass = (try? Validation.validatePendingTerms(db, noteIds: nil))
                ?? Validation.PassResult()
            termsActivated = validationPass.activated
            termsRejected = validationPass.rejected
                + ((try? Validation.rejectStalePending(db)) ?? 0)
            reviewPass = (try? EnrichmentReview.flagDisagreements(db, now: now)) ?? .init()
            
            try markConsolidated(db, now: now)
        }
        
        let decay: (decayed: Int, pruned: Int) = (0, 0)
        let vectorBuild = (try? Vectors.build())
        let summary = IntegrateResult.Summary(
            eventsCompacted: eventsCompacted,
            smallAxes: axisSummary.small.count,
            largeAxes: axisSummary.large.count,
            rareTags: tagSummary.rare.count,
            unusedVocabTags: tagSummary.unused.count,
            emptyAxesPruned: prunedAxesCount,
            unusedVocabPruned: prunedTagsCount,
            resolvedRipplePruned: prunedRippleFlags,
            ftsOrphansPruned: ftsPrune.orphansPruned,
            ftsRefilled: ftsPrune.refilled,
            integrityL1Issues: 0,
            linksDecayed: decay.decayed,
            linksPruned: decay.pruned,
            sourcesRechecked: sourceVerify.rechecked,
            sourcesBecameStale: sourceVerify.becameStale,
            sourcesRecovered: sourceVerify.recovered,
            sourcesMissing: sourceVerify.missing,
            sourcesUnreadable: sourceVerify.unreadable.count,
            termsActivated: termsActivated,
            termsRejected: termsRejected,
            enrichReviewFlagged: reviewPass.flagged,
            enrichReviewResolved: reviewPass.resolved,
            vectorsBuilt: (vectorBuild?.skipped == false) ? (vectorBuild?.noteCount ?? 0) : 0
        )
        var tracePayload: [String: Any?] = [
            "action": "integrate",
            "events_compacted": eventsCompacted
        ]
        
        if let data = try? JSONEncoder().encode(summary),
            let dictionary = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for (key, value) in dictionary { tracePayload[key] = value }
        }
        
        Events.record(kind: Events.kindConsolidation, payload: tracePayload, ts: now)
        
        return IntegrateResult(
            summary: summary,
            axisReport: IntegrateResult.AxisReportOutput(
                all: axisSummary.all.map { entry in
                    .init(axis: entry.axis, description: entry.description, count: entry.count)
                },
                small: axisSummary.small.map { entry in
                    .init(axis: entry.axis, count: entry.count)
                },
                large: axisSummary.large.map { entry in
                    .init(axis: entry.axis, count: entry.count)
                }
            ),
            tagReport: IntegrateResult.TagReportOutput(
                rare: tagSummary.rare.map { entry in .init(tag: entry.tag, count: entry.count) },
                unused: tagSummary.unused
            ),
            prune: IntegrateResult.PruneReport(
                axes: .init(pruned: prunedAxes, count: prunedAxesCount),
                tagVocab: .init(pruned: prunedTags, count: prunedTagsCount)
            ),
            integrityL1: IntegrateResult.IntegrityReport(checked: 0, issues: [])
        )
    }
}
