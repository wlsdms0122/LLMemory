//
//  ConsolidateService.swift
//  LLMemory
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import Storage

// Consolidation-domain service — the periodic hygiene passes.
public struct ConsolidateService: ConsolidateServiceable {
    // MARK: - Property
    let homeostasisWatermarkKey = "homeostasis.window_watermark"
    let homeostasisSeenKey = "homeostasis.expand_seen"
    let homeostasisLandedKey = "homeostasis.expand_landed"

    // The thresholds the tick judges by, read off the brain being adjusted.
    func homeostasisMinSample(_ config: Config) -> Int {
        config.getInt("homeostasis.min_sample", default: 50)
    }

    func homeostasisLowRate(_ config: Config) -> Double {
        config.getDouble("homeostasis.low_rate", default: 0.02)
    }

    func homeostasisHighRate(_ config: Config) -> Double {
        config.getDouble("homeostasis.high_rate", default: 0.15)
    }

    // Candidate-kind catalog — code-owned vocabulary for the surfacing CLI.
    public let candidateRetrievalKinds = CandidateDetector.retrievalKinds
    public let candidateStructuralKinds = CandidateDetector.structuralKinds
    public var candidateValidKinds: [String] { CandidateDetector.validKinds }

    let storage: GRDBStorage
    let brain: BrainContext
    let keywords: any KeywordExtracting

    // The enrichment keys and defaults have one owner; this resolves them
    // from this brain each time they are needed.
    var enrichment: EnrichmentTuning { EnrichmentTuning(brain.config) }

    private var detector: CandidateDetector { CandidateDetector(brain: brain) }

    // MARK: - Initializer
    init(storage: GRDBStorage, brain: BrainContext, keywords: any KeywordExtracting) {
        self.storage = storage
        self.brain = brain
        self.keywords = keywords
    }

    // MARK: - Public
    public func candidates(
        kinds: [String],
        limit: Int
    ) async throws -> [String: CandidateBatch] {
        // The string→Kind conversion happens once, at the API boundary — an
        // unknown kind is a caller bug, not an empty result.
        let resolved = try kinds.map { raw in
            guard let kind = CandidateDetector.Kind(rawValue: raw) else {
                throw CandidateError.unknownKind(raw)
            }

            return kind
        }

        return try await storage.read { scope in
            try candidateBatches(scope, kinds: resolved, limit: limit)
        }
    }

    // The detector dispatch — one batch per requested kind; the closed enum
    // makes the switch exhaustive, so a new kind cannot be forgotten here.
    func candidateBatches(
        _ scope: GRDBReadScope,
        kinds: [CandidateDetector.Kind],
        limit: Int
    ) throws -> [String: CandidateBatch] {
        var batches: [String: CandidateBatch] = [:]

        for kind in kinds {
            switch kind {
            case .split:
                batches[kind.rawValue] = .split(try detector.splitCandidates(scope, limit: limit))

            case .reconsolidate:
                batches[kind.rawValue] = .flagged(try detector.reconsolidateCandidates(scope, limit: limit))

            case .ripple:
                batches[kind.rawValue] = .flagged(try detector.rippleCandidates(scope, limit: limit))

            case .enrichReview:
                batches[kind.rawValue] = .flagged(try detector.enrichReviewCandidates(scope, limit: limit))

            case .clusters:
                batches[kind.rawValue] = .clusters(try detector.clusters(scope, limit: limit))

            case .missingEdge:
                batches[kind.rawValue] = .missingEdge(try detector.missingEdges(scope, limit: limit))

            case .nearDuplicate:
                batches[kind.rawValue] = .nearDuplicate(try detector.nearDuplicates(scope, limit: limit))
            }
        }

        return batches
    }

    public func integrate() async throws -> IntegrateResult {
        try await storage.run { scope in
            var result = try integrate(scope)
            let integrity = try scope.run(CheckCorpusIntegrityL1Transaction())
            result.integrityL1 = IntegrateResult.IntegrityReport(
                checked: integrity.checked,
                issues: integrity.issues
            )
            result.summary.integrityL1Issues = integrity.issues.count

            return result
        }
    }

    public func homeostasis() async throws -> HomeostasisReport {
        let now = Int(Date().timeIntervalSince1970)
        let report = try await storage.run { scope in
            _ = try scope.run(DeriveActivityWindowsTransaction(now: now, windowGapSec: ActivationTuning(brain).windowGapSec))

            let report = try homeostasisTick(scope, now: now)

            // The run happened whether or not its trace lands — losing the
            // trace must not undo the consolidation it describes.
            try? scope.run(
                RecordEventTransaction(
                    kind: .consolidation,
                    payload: EventPayload([
                        "action": "homeostasis",
                        "windows_processed": .integer(report.windowsProcessed),
                        "adjusted_gene": report.adjustedGene.map { gene in .string(gene) },
                        "note": .string(report.note)
                    ]),
                    ts: now
                )
            )

            return report
        }

        return report
    }

    public func prune() async throws -> PruneResult {
        try await storage.run { scope in try prune(scope) }
    }

    public func report() async throws -> ConsolidateTagReport {
        try await storage.read { scope in try scope.run(FetchTagReportTransaction()) }
    }

    // MARK: - Internal

    // B: synaptic pruning — decays the learned edges and cuts those below
    // the floor. Rare by design; structure loss is the point.
    func prune(_ scope: GRDBScope) throws -> PruneResult {
        let now = Int(Date().timeIntervalSince1970)
        let decay = try scope.run(
            DecayAndPruneLinksTransaction(
                factor: brain.genes.double("links.decay_factor"),
                floor: brain.genes.double("links.prune_floor")
            )
        )

        try? scope.run(
            RecordEventTransaction(
                kind: .consolidation,
                payload: EventPayload([
                    "action": "prune",
                    "links_decayed": .integer(decay.decayed),
                    "links_pruned": .integer(decay.pruned)
                ]),
                ts: now
            )
        )

        return PruneResult(linksDecayed: decay.decayed, linksPruned: decay.pruned)
    }

    // A: non-destructive integration — succession, retention compaction,
    // hygiene prunes, term validation, disagreement review, vector rebuild.
    func integrate(_ scope: GRDBScope) throws -> IntegrateResult {
        let now = Int(Date().timeIntervalSince1970)
        let retentionSec = brain.config.getInt("events.retention_days", default: 30) * 24 * 60 * 60

        _ = try scope.run(DeriveActivityWindowsTransaction(now: now, windowGapSec: ActivationTuning(brain).windowGapSec))

        let eventsCompacted = try scope.run(
            CompactOldEventsTransaction(now: now, retentionSec: retentionSec)
        ).compacted
        let tagSummary = try scope.run(FetchTagReportTransaction())
        let sourceVerify = try SourceVerifier().verifyAll(scope, brain, now: now)

        let prunedTags = try scope.run(PruneUnusedVocabTagsTransaction())
        let prunedRippleFlags = try scope.run(
            PruneResolvedRippleFlagsTransaction(now: now)
        )

        _ = try scope.run(
            PruneOldLifecycleEventsTransaction(
                now: now,
                retentionDays: brain.config.getInt("lifecycle.retention_days", default: 180)
            )
        )

        let ftsPrune = try scope.run(PruneFtsOrphansTransaction())

        // Best-effort passes run as savepointed attempts — a failure rolls
        // its own statements back and is reported by name instead of being
        // silently indistinguishable from "nothing to do".
        var degradedPasses: [String] = []

        func degrade(_ name: String, _ error: any Error) {
            degradedPasses.append("\(name): \(error)")
        }

        var validationPass = TermValidationPass()
        var staleRejected = 0
        var reviewPass = EnrichmentReviewPass()

        switch try scope.attempt({ try scope.run(
            ValidatePendingTermsTransaction(
                noteIds: nil,
                keywords: keywords,
                roundtripTopK: enrichment.roundtripTopK,
                idfDFCeiling: enrichment.idfDFCeiling
            )
        ) }) {
        case .success(let pass): validationPass = pass
        case .failure(let error): degrade("term_validation", error)
        }

        switch try scope.attempt({ try scope.run(RejectStalePendingTermsTransaction()) }) {
        case .success(let rejected): staleRejected = rejected
        case .failure(let error): degrade("stale_rejection", error)
        }

        switch try scope.attempt({ try scope.run(
            FlagEnrichmentDisagreementsTransaction(
                now: now,
                disagreeFloor: enrichment.disagreeFloor
            )
        ) }) {
        case .success(let pass): reviewPass = pass
        case .failure(let error): degrade("enrich_review", error)
        }

        let termsActivated = validationPass.activated
        let termsRejected = validationPass.rejected + staleRejected

        let decay: (decayed: Int, pruned: Int) = (0, 0)
        var vectorBuild: VectorBuildResult?

        switch try scope.attempt({ try scope.run(
            BuildVectorsTransaction(dimension: brain.config.getInt("vectors.dim", default: 48))
        ) }) {
        case .success(let build): vectorBuild = build
        case .failure(let error): degrade("vector_build", error)
        }
        let summary = IntegrateResult.Summary(
            eventsCompacted: eventsCompacted,
            rareTags: tagSummary.rare.count,
            unusedVocabTags: tagSummary.unused.count,
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
            vectorsBuilt: (vectorBuild?.skipped == false) ? (vectorBuild?.noteCount ?? 0) : 0,
            degradedPasses: degradedPasses
        )
        var tracePayload: [String: JSONValue?] = [
            "action": "integrate",
            "events_compacted": .integer(eventsCompacted)
        ]

        // The summary is already a Codable shape, so it arrives as payload
        // values rather than as Any that has to be re-inspected on the way in.
        if let data = try? JSONEncoder().encode(summary),
            let decoded = try? JSONDecoder().decode([String: JSONValue].self, from: data) {
            for (key, value) in decoded { tracePayload[key] = value }
        }

        try? scope.run(
            RecordEventTransaction(kind: .consolidation, payload: EventPayload(tracePayload), ts: now)
        )

        return IntegrateResult(
            summary: summary,
            tagReport: tagSummary,
            prune: IntegrateResult.PruneReport(
                tagVocab: .init(pruned: prunedTags, count: prunedTags.count)
            ),
            integrityL1: IntegrateResult.IntegrityReport(checked: 0, issues: [])
        )
    }

    // The deterministic metaplasticity tick — reacts only to measured waste
    // (expand hits that never land), one step, within bounds, wild-type as
    // the ceiling. Windows are consumed exactly once via the watermark.
    func homeostasisTick(_ scope: GRDBScope, now: Int) throws -> HomeostasisReport {
        let watermark = Int(
            try scope.run(FetchConfigValueTransaction(key: homeostasisWatermarkKey, default: "0"))
        ) ?? 0
        let closedBefore = now - brain.genes.int("activation.window_gap_sec")
        let windows = try scope.run(
            FetchClosedActivityWindowsTransaction(watermark: watermark, closedBefore: closedBefore)
        )

        let minSample = homeostasisMinSample(brain.config)
        let lowRate = homeostasisLowRate(brain.config)
        let highRate = homeostasisHighRate(brain.config)
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
        var note = "accumulating (\(sampleSeen)/\(minSample) expand hits)"

        if sampleSeen >= minSample {
            evaluated = true

            let landingRate = Double(sampleLanded) / Double(sampleSeen)
            rate = landingRate

            let gene = "related.expand_hops"
            let bounds = Genes.gene(gene)!
            let wildType = bounds.wildType
            // From the row, not the process cache — the tick reads the value
            // it is about to move, and it moves it in this same scope.
            let current = try scope.run(FetchGeneValueTransaction(geneId: gene))
                ?? brain.config.getDouble(gene, default: wildType)
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
                let result = try scope.run(
                    ApplyGeneValueTransaction(
                        geneId: gene,
                        value: target,
                        cause: "homeostasis:expand_landing",
                        detail: "rate=\(String(format: "%.4f", landingRate)) n=\(sampleSeen)",
                        requireMutable: true,
                        ts: now,
                        configured: brain.config.double(gene)
                    )
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
