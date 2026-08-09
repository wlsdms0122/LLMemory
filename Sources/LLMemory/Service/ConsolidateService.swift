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
        try await storage.run { scope in
            var result = try integrate(scope)
            let integrity = try scope.run(CheckCorpusIntegrityL1Transaction())
            result.integrityL1 = Consolidation.IntegrateResult.IntegrityReport(
                checked: integrity.checked,
                issues: integrity.issues
            )
            result.summary.integrityL1Issues = integrity.issues.count

            return result
        }
    }

    public static func homeostasis(_ storage: GRDBStorage) async throws -> HomeostasisReport {
        let now = Int(Date().timeIntervalSince1970)

        do {
            return try await run(storage, now: now)
        } catch {
            // The tick may have primed the gene cache before the scope rolled
            // back — repair it from committed state before surfacing the error.
            if let values = try? await storage.read({ scope in
                try scope.run(FetchGenomeValuesTransaction())
            }) {
                Genes.warm(values)
            }

            throw error
        }
    }

    private static func run(_ storage: GRDBStorage, now: Int) async throws -> HomeostasisReport {
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
        try await storage.run { scope in try prune(scope) }
    }

    public static func report(
        _ storage: GRDBStorage
    ) async throws -> (axis: Consolidation.AxisReport, tag: Consolidation.TagReport) {
        try await storage.read { scope in
            (
                axis: try scope.run(FetchAxisReportTransaction()),
                tag: try scope.run(FetchTagReportTransaction())
            )
        }
    }

    // MARK: - Internal

    // B: synaptic pruning — decays the learned edges and cuts those below
    // the floor. Rare by design; structure loss is the point.
    static func prune(_ scope: GRDBScope) throws -> Consolidation.PruneResult {
        let now = Int(Date().timeIntervalSince1970)
        let decay = try scope.run(DecayAndPruneLinksTransaction())

        try scope.run(
            RecordEventTransaction(
                kind: Events.kindConsolidation,
                payload: [
                    "action": "prune",
                    "links_decayed": decay.decayed,
                    "links_pruned": decay.pruned
                ],
                ts: now
            )
        )

        return Consolidation.PruneResult(linksDecayed: decay.decayed, linksPruned: decay.pruned)
    }

    // A: non-destructive integration — succession, retention compaction,
    // hygiene prunes, term validation, disagreement review, vector rebuild.
    static func integrate(_ scope: GRDBScope) throws -> Consolidation.IntegrateResult {
        let now = Int(Date().timeIntervalSince1970)
        let retentionSec = Config.getInt("events.retention_days", default: 30) * 24 * 60 * 60

        _ = try scope.run(DeriveActivityWindowsTransaction(now: now))

        let eventsCompacted = try scope.run(
            CompactOldEventsTransaction(now: now, retentionSec: retentionSec)
        ).compacted
        let axisSummary = try scope.run(FetchAxisReportTransaction())
        let tagSummary = try scope.run(FetchTagReportTransaction())
        let sourceVerify = try scope.run(VerifySourcesTransaction(now: now))

        let prunedAxes = try scope.run(PruneEmptyAxesTransaction())
        let prunedTags = try scope.run(PruneUnusedVocabTagsTransaction())
        let prunedRippleFlags = try scope.run(
            PruneResolvedRippleFlagsTransaction(now: now)
        )

        _ = try scope.run(
            PruneOldLifecycleEventsTransaction(
                now: now,
                retentionDays: Config.getInt("lifecycle.retention_days", default: 180)
            )
        )

        let ftsPrune = try scope.run(PruneFtsOrphansTransaction())

        let validationPass = (try? scope.run(ValidatePendingTermsTransaction(noteIds: nil)))
            ?? TermValidationPass()
        let termsActivated = validationPass.activated
        let termsRejected = validationPass.rejected
            + ((try? scope.run(RejectStalePendingTermsTransaction())) ?? 0)
        let reviewPass = (try? scope.run(FlagEnrichmentDisagreementsTransaction(now: now))) ?? .init()

        try scope.run(MarkConsolidatedTransaction(now: now))

        let decay: (decayed: Int, pruned: Int) = (0, 0)
        let vectorBuild = try? scope.run(BuildVectorsTransaction())
        let summary = Consolidation.IntegrateResult.Summary(
            eventsCompacted: eventsCompacted,
            smallAxes: axisSummary.small.count,
            largeAxes: axisSummary.large.count,
            rareTags: tagSummary.rare.count,
            unusedVocabTags: tagSummary.unused.count,
            emptyAxesPruned: prunedAxes.count,
            unusedVocabPruned: prunedTags.count,
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

        try scope.run(
            RecordEventTransaction(kind: Events.kindConsolidation, payload: tracePayload, ts: now)
        )

        return Consolidation.IntegrateResult(
            summary: summary,
            axisReport: Consolidation.IntegrateResult.AxisReportOutput(
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
            tagReport: Consolidation.IntegrateResult.TagReportOutput(
                rare: tagSummary.rare.map { entry in .init(tag: entry.tag, count: entry.count) },
                unused: tagSummary.unused
            ),
            prune: Consolidation.IntegrateResult.PruneReport(
                axes: .init(pruned: prunedAxes, count: prunedAxes.count),
                tagVocab: .init(pruned: prunedTags, count: prunedTags.count)
            ),
            integrityL1: Consolidation.IntegrateResult.IntegrityReport(checked: 0, issues: [])
        )
    }

    // The deterministic metaplasticity tick — reacts only to measured waste
    // (expand hits that never land), one step, within bounds, wild-type as
    // the ceiling. Windows are consumed exactly once via the watermark.
    static func homeostasisTick(_ scope: GRDBScope, now: Int) throws -> HomeostasisReport {
        let watermark = Int(
            try scope.run(FetchConfigValueTransaction(key: homeostasisWatermarkKey, default: "0"))
        ) ?? 0
        let closedBefore = now - Genes.int("activation.window_gap_sec")
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
            let current = Genes.double(gene)
            let wildType = Genes.gene(gene)!.wildType
            let bounds = Genes.gene(gene)!
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
