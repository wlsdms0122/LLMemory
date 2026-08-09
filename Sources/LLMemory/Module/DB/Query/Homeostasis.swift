//
//  Homeostasis.swift
//  LLMemory
//
//  Created by JSilver on 8/7/26.
//

import Foundation
import GRDB

public enum Homeostasis {
    public struct Report: Encodable {
        enum CodingKeys: String, CodingKey {
            case windowsProcessed = "windows_processed"
            case expandSeen = "expand_seen"
            case expandLanded = "expand_landed"
            case sampleSeen = "sample_seen"
            case sampleLanded = "sample_landed"
            case evaluated
            case landingRate = "landing_rate"
            case adjustedGene = "adjusted_gene"
            case oldValue = "old_value"
            case newValue = "new_value"
            case note
        }
        
        // MARK: - Property
        public let windowsProcessed: Int
        public let expandSeen: Int
        public let expandLanded: Int
        public let sampleSeen: Int
        public let sampleLanded: Int
        public let evaluated: Bool
        public let landingRate: Double?
        public let adjustedGene: String?
        public let oldValue: Double?
        public let newValue: Double?
        public let note: String
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    // MARK: - Property
    static let watermarkKey = "homeostasis.window_watermark"
    static let seenKey = "homeostasis.expand_seen"
    static let landedKey = "homeostasis.expand_landed"
    
    static var minSample: Int { Config.getInt("homeostasis.min_sample", default: 50) }
    static var lowRate: Double { Config.getDouble("homeostasis.low_rate", default: 0.02) }
    static var highRate: Double { Config.getDouble("homeostasis.high_rate", default: 0.15) }
    
    // MARK: - Initializer
    // MARK: - Public
    public static func tick(_ db: Database, now: Int) throws -> Report {
        let watermark = Int(Config.getStringTx(watermarkKey, default: "0", txDB: db)) ?? 0
        let closedBefore = now - Genome.int("activation.window_gap_sec")
        let firstGet = try Int.fetchOne(
            db,
            sql: "SELECT MIN(surfaced_at) FROM retrieval_hits WHERE cmd = 'get'"
        )
        let sightedSince = firstGet ?? Int.max
        let candidates = try Row.fetchAll(db, sql: """
            SELECT id, ended_at, started_at FROM activity_windows WHERE id > ?
            ORDER BY id
            """, arguments: [watermark])
        var windows: [(id: Int, sighted: Bool)] = []
        
        for candidate in candidates {
            let endedAt: Int = candidate["ended_at"]
            
            if endedAt >= closedBefore { break }
            
            let startedAt: Int = candidate["started_at"]
            windows.append((id: candidate["id"], sighted: startedAt >= sightedSince))
        }
        
        var cohortSeen = 0
        var cohortLanded = 0
        var lastWindow = watermark
        
        for window in windows {
            lastWindow = window.id
            
            guard window.sighted else { continue }
            
            let rows = try Row.fetchAll(db, sql: """
                SELECT h.note_id, h.surfaced_at,
                       EXISTS (
                         SELECT 1 FROM retrieval_hits g
                         WHERE g.window_id = h.window_id AND g.note_id = h.note_id
                           AND g.cmd = 'get' AND g.surfaced_at >= h.surfaced_at
                       ) AS landed
                FROM retrieval_hits h
                WHERE h.window_id = ? AND h.surface_kind = 'expand' AND h.cmd != 'get'
                """, arguments: [window.id])
            
            cohortSeen += rows.count
            cohortLanded += rows.filter { row in (row["landed"] as Int? ?? 0) == 1 }.count
        }
        
        let sampleSeen = (Int(Config.getStringTx(seenKey, default: "0", txDB: db)) ?? 0)
            + cohortSeen
        let sampleLanded = (Int(Config.getStringTx(landedKey, default: "0", txDB: db)) ?? 0)
            + cohortLanded
        var remainderSeen = sampleSeen
        var remainderLanded = sampleLanded
        var evaluated = false
        var rate: Double? = nil
        var adjustedGene: String? = nil
        var oldValue: Double? = nil
        var newValue: Double? = nil
        var note = "accumulating (\(sampleSeen)/\(minSample) expand hits)"
        
        if sampleSeen >= minSample {
            evaluated = true
            
            let landingRate = Double(sampleLanded) / Double(sampleSeen)
            rate = landingRate
            
            let gene = "related.expand_hops"
            let current = Genome.double(gene)
            let wildType = Genome.gene(gene)!.wildType
            let bounds = Genome.gene(gene)!
            var target = current
            
            if landingRate < lowRate && current > bounds.min {
                target = current - 1
                note = "expand landing rate \(String(format: "%.3f", landingRate)) < \(lowRate) — narrowing"
            } else if landingRate > highRate && current < wildType {
                target = current + 1
                note = "expand landing rate \(String(format: "%.3f", landingRate)) > \(highRate) — restoring toward wild-type"
            } else {
                note = "expand landing rate \(String(format: "%.3f", landingRate)) — within band, no adjustment"
            }
            
            if target != current {
                let result = try GenomeService.setGene(
                    GRDBScope(db),
                    id: gene,
                    value: target,
                    cause: "homeostasis:expand_landing",
                    detail: "rate=\(String(format: "%.4f", landingRate)) n=\(sampleSeen)",
                    requireMutable: true,
                    now: now
                )
                adjustedGene = gene
                oldValue = result.old
                newValue = result.new
            }
            
            remainderSeen = 0
            remainderLanded = 0
        }
        
        try Config.set(watermarkKey, value: lastWindow, txDB: db)
        try Config.set(seenKey, value: remainderSeen, txDB: db)
        try Config.set(landedKey, value: remainderLanded, txDB: db)
        
        return Report(
            windowsProcessed: windows.count,
            expandSeen: cohortSeen,
            expandLanded: cohortLanded,
            sampleSeen: sampleSeen,
            sampleLanded: sampleLanded,
            evaluated: evaluated,
            landingRate: rate,
            adjustedGene: adjustedGene,
            oldValue: oldValue,
            newValue: newValue,
            note: note
        )
    }
    
    // MARK: - Private
}
