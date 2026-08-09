//
//  ConsolidateService.swift
//  LLMemory
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import Storage

// Consolidation-domain service — the periodic hygiene passes.
public enum ConsolidateService {
    public struct HomeostasisReport: Encodable, Sendable {
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
    static let homeostasisWatermarkKey = "homeostasis.window_watermark"
    static let homeostasisSeenKey = "homeostasis.expand_seen"
    static let homeostasisLandedKey = "homeostasis.expand_landed"

    static var homeostasisMinSample: Int { Config.getInt("homeostasis.min_sample", default: 50) }
    static var homeostasisLowRate: Double { Config.getDouble("homeostasis.low_rate", default: 0.02) }
    static var homeostasisHighRate: Double { Config.getDouble("homeostasis.high_rate", default: 0.15) }

    // Candidate-kind catalog — code-owned vocabulary for the surfacing CLI.
    public static let candidateRetrievalKinds = Candidates.retrievalKinds
    public static let candidateStructuralKinds = Candidates.structuralKinds
    public static var candidateValidKinds: [String] { Candidates.validKinds }

    // MARK: - Initializer
    // MARK: - Public
    public static func candidates(
        _ storage: GRDBStorage,
        kinds: [String],
        limit: Int
    ) async throws -> [String: Candidates.Batch] {
        try await storage.read { scope in
            try scope.run(FetchCandidateBatchesTransaction(kinds: kinds, limit: limit))
        }
    }

    public static func integrate(_ storage: GRDBStorage) async throws -> Consolidation.IntegrateResult {
        try await storage.run(IntegrateTransaction())
    }

    public static func homeostasis(_ storage: GRDBStorage) async throws -> HomeostasisReport {
        let now = Int(Date().timeIntervalSince1970)
        let report = try await storage.run { scope in
            _ = try scope.run(DeriveActivityWindowsTransaction(now: now))

            let report = try homeostasisTick(scope, now: now)

            try scope.run(
                RecordEventTransaction(
                    kind: Events.kindConsolidation,
                    payload: [
                        "action": "homeostasis",
                        "windows_processed": report.windowsProcessed,
                        "adjusted_gene": report.adjustedGene as Any?,
                        "note": report.note
                    ],
                    ts: now
                )
            )

            return report
        }

        return report
    }

    public static func prune(_ storage: GRDBStorage) async throws -> Consolidation.PruneResult {
        try await storage.run(PruneTransaction())
    }

    public static func report(
        _ storage: GRDBStorage
    ) async throws -> (axis: Consolidation.AxisReport, tag: Consolidation.TagReport) {
        try await storage.run(ConsolidateReportTransaction())
    }

    // MARK: - Internal
    // The deterministic metaplasticity tick — reacts only to measured waste
    // (expand hits that never land), one step, within bounds, wild-type as
    // the ceiling. Windows are consumed exactly once via the watermark.
    static func homeostasisTick(_ scope: GRDBScope, now: Int) throws -> HomeostasisReport {
        let watermark = Int(
            try scope.run(FetchConfigValueTransaction(key: homeostasisWatermarkKey, default: "0"))
        ) ?? 0
        let closedBefore = now - Genome.int("activation.window_gap_sec")
        let windows = try scope.run(
            FetchClosedActivityWindowsTransaction(watermark: watermark, closedBefore: closedBefore)
        )

        var cohortSeen = 0
        var cohortLanded = 0
        var lastWindow = watermark

        for window in windows {
            lastWindow = window.id

            guard window.sighted else { continue }

            let evidence = try scope.run(FetchExpandEvidenceTransaction(windowId: window.id))

            cohortSeen += evidence.seen
            cohortLanded += evidence.landed
        }

        let sampleSeen = (Int(
            try scope.run(FetchConfigValueTransaction(key: homeostasisSeenKey, default: "0"))
        ) ?? 0) + cohortSeen
        let sampleLanded = (Int(
            try scope.run(FetchConfigValueTransaction(key: homeostasisLandedKey, default: "0"))
        ) ?? 0) + cohortLanded
        var remainderSeen = sampleSeen
        var remainderLanded = sampleLanded
        var evaluated = false
        var rate: Double? = nil
        var adjustedGene: String? = nil
        var oldValue: Double? = nil
        var newValue: Double? = nil
        var note = "accumulating (\(sampleSeen)/\(homeostasisMinSample) expand hits)"

        if sampleSeen >= homeostasisMinSample {
            evaluated = true

            let landingRate = Double(sampleLanded) / Double(sampleSeen)
            rate = landingRate

            let gene = "related.expand_hops"
            let current = Genome.double(gene)
            let wildType = Genome.gene(gene)!.wildType
            let bounds = Genome.gene(gene)!
            var target = current

            if landingRate < homeostasisLowRate && current > bounds.min {
                target = current - 1
                note = "expand landing rate \(String(format: "%.3f", landingRate)) < \(homeostasisLowRate) — narrowing"
            } else if landingRate > homeostasisHighRate && current < wildType {
                target = current + 1
                note = "expand landing rate \(String(format: "%.3f", landingRate)) > \(homeostasisHighRate) — restoring toward wild-type"
            } else {
                note = "expand landing rate \(String(format: "%.3f", landingRate)) — within band, no adjustment"
            }

            if target != current {
                let result = try GenomeService.setGene(
                    scope,
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

        try scope.run(SetConfigValueTransaction(key: homeostasisWatermarkKey, value: String(lastWindow)))
        try scope.run(SetConfigValueTransaction(key: homeostasisSeenKey, value: String(remainderSeen)))
        try scope.run(SetConfigValueTransaction(key: homeostasisLandedKey, value: String(remainderLanded)))

        return HomeostasisReport(
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
