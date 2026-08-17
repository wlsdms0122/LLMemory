//
//  ConsolidateService.swift
//  LLMemory
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import GRDB

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

    let storage: any GRDBStorable
    let brain: BrainContext
    let keywords: any KeywordExtracting

    // The enrichment keys and defaults have one owner; this resolves them
    // from this brain each time they are needed.
    var enrichment: EnrichmentTuning { EnrichmentTuning(brain.config) }

    private let detector: CandidateDetector

    private let corpus = CorpusReconciler()

    // MARK: - Initializer
    init(storage: any GRDBStorable, brain: BrainContext, keywords: any KeywordExtracting) {
        self.storage = storage
        self.brain = brain
        self.detector = CandidateDetector(brain: brain)
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

        return try await storage.read { db in
            try candidateBatches(db, kinds: resolved, limit: limit)
        }
    }

    // The detector dispatch — one batch per requested kind; the closed enum
    // makes the switch exhaustive, so a new kind cannot be forgotten here.
    func candidateBatches(
        _ db: Database,
        kinds: [CandidateDetector.Kind],
        limit: Int
    ) throws -> [String: CandidateBatch] {
        var batches: [String: CandidateBatch] = [:]

        for kind in kinds {
            switch kind {
            case .split:
                batches[kind.rawValue] = .split(try detector.splitCandidates(db, limit: limit))

            case .reconsolidate:
                batches[kind.rawValue] = .flagged(try detector.reconsolidateCandidates(db, limit: limit))

            case .ripple:
                batches[kind.rawValue] = .flagged(try detector.rippleCandidates(db, limit: limit))

            case .enrichReview:
                batches[kind.rawValue] = .flagged(try detector.enrichReviewCandidates(db, limit: limit))

            case .clusters:
                batches[kind.rawValue] = .clusters(try detector.clusters(db, limit: limit))

            case .missingEdge:
                batches[kind.rawValue] = .missingEdge(try detector.missingEdges(db, limit: limit))

            case .nearDuplicate:
                batches[kind.rawValue] = .nearDuplicate(try detector.nearDuplicates(db, limit: limit))
            }
        }

        return batches
    }

    public func integrate() async throws -> IntegrateResult {
        try await storage.write { db in
            var result = try integrate(db)
            let integrity = try corpus.checkFilesPresent(db, brain)
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
        let report = try await storage.write { db in
            _ = try DeriveActivityWindowsOperation(now: now, windowGapSec: ActivationTuning(brain).windowGapSec).execute(db)

            let report = try homeostasisTick(db, now: now)

            // The run happened whether or not its trace lands — losing the
            // trace must not undo the consolidation it describes.
            try? RecordEventOperation(
                kind: .consolidation,
                payload: EventPayload([
                    "action": "homeostasis",
                    "windows_processed": .integer(report.windowsProcessed),
                    "adjusted_gene": report.adjustedGene.map { gene in .string(gene) },
                    "note": .string(report.note)
                ]),
                ts: now
            ).execute(db)

            return report
        }

        return report
    }

    public func prune() async throws -> PruneResult {
        try await storage.write { db in try prune(db) }
    }

    public func report() async throws -> ConsolidateTagReport {
        try await storage.run(FetchTagReportOperation())
    }

    // MARK: - Internal

    // B: synaptic pruning — decays the learned edges and cuts those below
    // the floor. Rare by design; structure loss is the point.
    func prune(_ db: Database) throws -> PruneResult {
        let now = Int(Date().timeIntervalSince1970)
        let decay = try DecayAndPruneLinksOperation(
            factor: brain.genes.double("links.decay_factor"),
            floor: brain.genes.double("links.prune_floor")
        ).execute(db)

        try? RecordEventOperation(
            kind: .consolidation,
            payload: EventPayload([
                "action": "prune",
                "links_decayed": .integer(decay.decayed),
                "links_pruned": .integer(decay.pruned)
            ]),
            ts: now
        ).execute(db)

        return PruneResult(linksDecayed: decay.decayed, linksPruned: decay.pruned)
    }

    // A: non-destructive integration — succession, retention compaction,
    // hygiene prunes, term validation, disagreement review, vector rebuild.
    func integrate(_ db: Database) throws -> IntegrateResult {
        let now = Int(Date().timeIntervalSince1970)
        let retentionSec = brain.config.getInt("events.retention_days", default: 30) * 24 * 60 * 60

        _ = try DeriveActivityWindowsOperation(now: now, windowGapSec: ActivationTuning(brain).windowGapSec).execute(db)

        let eventsCompacted = try CompactOldEventsOperation(now: now, retentionSec: retentionSec).execute(db).compacted
        let tagSummary = try FetchTagReportOperation().execute(db)
        let sourceVerify = try SourceVerifier().verifyAll(db, brain, now: now)

        let prunedTags = try PruneUnusedVocabTagsOperation().execute(db)
        let prunedRippleFlags = try PruneResolvedRippleFlagsOperation(now: now).execute(db)

        _ = try PruneOldLifecycleEventsOperation(
            now: now,
            retentionDays: brain.config.getInt("lifecycle.retention_days", default: 180)
        ).execute(db)

        let ftsPrune = try corpus.reconcileSearchIndex(db, brain)

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

        switch try db.attempt({ try ValidatePendingTermsOperation(
            noteIds: nil,
            keywords: keywords,
            roundtripTopK: enrichment.roundtripTopK,
            idfDFCeiling: enrichment.idfDFCeiling
        ).execute(db) }) {
        case .success(let pass): validationPass = pass
        case .failure(let error): degrade("term_validation", error)
        }

        switch try db.attempt({ try RejectStalePendingTermsOperation().execute(db) }) {
        case .success(let rejected): staleRejected = rejected
        case .failure(let error): degrade("stale_rejection", error)
        }

        switch try db.attempt({ try FlagEnrichmentDisagreementsOperation(
            now: now,
            disagreeFloor: enrichment.disagreeFloor
        ).execute(db) }) {
        case .success(let pass): reviewPass = pass
        case .failure(let error): degrade("enrich_review", error)
        }

        let termsActivated = validationPass.activated
        let termsRejected = validationPass.rejected + staleRejected

        let decay: (decayed: Int, pruned: Int) = (0, 0)
        var vectorBuild: VectorBuildResult?

        switch try db.attempt({ try BuildVectorsOperation(dimension: brain.config.getInt("vectors.dim", default: 48)).execute(db) }) {
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

        try? RecordEventOperation(kind: .consolidation, payload: EventPayload(tracePayload), ts: now).execute(db)

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
    func homeostasisTick(_ db: Database, now: Int) throws -> HomeostasisReport {
        let watermark = Int(
            try FetchConfigValueOperation(key: homeostasisWatermarkKey, default: "0").execute(db)
        ) ?? 0
        let closedBefore = now - brain.genes.int("activation.window_gap_sec")
        let windows = try FetchClosedActivityWindowsOperation(watermark: watermark, closedBefore: closedBefore).execute(db)

        let minSample = homeostasisMinSample(brain.config)
        let lowRate = homeostasisLowRate(brain.config)
        let highRate = homeostasisHighRate(brain.config)
        var cohortSeen = 0
        var cohortLanded = 0
        var lastWindow = watermark

        for window in windows {
            lastWindow = window.id

            guard window.sighted else { continue }

            let evidence = try FetchExpandEvidenceOperation(windowId: window.id).execute(db)

            cohortSeen += evidence.seen
            cohortLanded += evidence.landed
        }

        let sampleSeen = (Int(
            try FetchConfigValueOperation(key: homeostasisSeenKey, default: "0").execute(db)
        ) ?? 0) + cohortSeen
        let sampleLanded = (Int(
            try FetchConfigValueOperation(key: homeostasisLandedKey, default: "0").execute(db)
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
            let current = try FetchGeneValueOperation(geneId: gene).execute(db)
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
                let result = try ApplyGeneValueOperation(
                    geneId: gene,
                    value: target,
                    cause: "homeostasis:expand_landing",
                    detail: "rate=\(String(format: "%.4f", landingRate)) n=\(sampleSeen)",
                    requireMutable: true,
                    ts: now,
                    configured: brain.config.double(gene)
                ).execute(db)
                adjustedGene = gene
                oldValue = result.old
                newValue = result.new
            }

            remainderSeen = 0
            remainderLanded = 0
        }

        try SetConfigValueOperation(key: homeostasisWatermarkKey, value: String(lastWindow)).execute(db)
        try SetConfigValueOperation(key: homeostasisSeenKey, value: String(remainderSeen)).execute(db)
        try SetConfigValueOperation(key: homeostasisLandedKey, value: String(remainderLanded)).execute(db)

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
