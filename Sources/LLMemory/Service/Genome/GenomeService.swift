//
//  GenomeService.swift
//  LLMemory
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import GRDB
import Storage

// Genome-domain service — the observation surfaces: the catalog with this
// brain's values, the provenance of every mutation, and offline reranking
// under a candidate value.
//
// It does not own the plasticity rules. What a gene admits is the catalog's
// (Genes.rejection), and writing a value is a transaction — both live in the
// module, where the callers that need them already are.
public struct GenomeService: GenomeServiceable {
    // MARK: - Property
    let storage: GRDBStorage
    let brain: BrainContext
    let keywords: any KeywordExtracting
    let entities: any EntityHinting

    // MARK: - Initializer
    init(
        storage: GRDBStorage,
        brain: BrainContext,
        keywords: any KeywordExtracting,
        entities: any EntityHinting
    ) {
        self.storage = storage
        self.brain = brain
        self.keywords = keywords
        self.entities = entities
    }

    // MARK: - Public
    // Maps the catalog against values fetched in this scope — no cache
    // mutation on the read path (read scopes read; only gated writers warm).
    // The connection gate stays: an uninitialized brain fails loud instead
    // of masquerading as wild-type.
    public func list() async throws -> [GeneListRow] {
        try await storage.read { db in
            catalogRows(brain.genes, values: try db.run(FetchGenomeValuesTransaction()))
        }
    }

    public func history(
        gene: String?,
        limit: Int
    ) async throws -> [GeneHistoryRow] {
        try await storage.read { db in
            try history(db, gene: gene, limit: limit)
        }
    }

    public func shadow(
        gene: String,
        value: Double,
        limit: Int,
        sampleDiffs: Int
    ) async throws -> GenomeShadowResult {
        try await storage.read { db in
            try shadow(db, gene: gene, value: value, limit: limit, sampleDiffs: sampleDiffs)
        }
    }

    // MARK: - Internal
    func history(
        _ db: Database,
        gene: String?,
        limit: Int
    ) throws -> [GeneHistoryRow] {
        try db.run(FetchGenomeEventsTransaction(geneId: gene, limit: limit))
            .map { event in
                GeneHistoryRow(
                    geneId: event.geneId,
                    oldValue: event.oldValue,
                    newValue: event.newValue,
                    cause: event.cause,
                    detail: event.detail,
                    ts: event.ts
                )
            }
    }

    // Offline reranking — replays the logged retrieval queries against the
    // current corpus under a candidate gene value. The candidate is task-local
    // to the replay: it never reaches the brain's cache, so a concurrent reader
    // of this brain cannot see it and nothing has to be put back afterwards.
    func shadow(
        _ db: Database,
        gene: String,
        value: Double,
        limit: Int,
        sampleDiffs: Int
    ) throws -> GenomeShadowResult {
        if let rejection = Genes.rejection(gene, value: value) { throw rejection }

        let baselineValue = brain.genes.double(gene)
        let logged = try db.run(FetchLoggedRetrievalQueriesTransaction(limit: limit))

        // The tuning is a parameter, not a capture: the candidate run is the
        // same replay under numbers resolved from a brain that answers one
        // gene differently, so the borrowed value reaches these transactions
        // and no others — and it does so as the number they actually used.
        func replayIds(
            _ db: Database,
            _ tuning: RetrievalTuning,
            _ loggedQuery: FetchLoggedRetrievalQueriesTransaction.LoggedQuery
        ) throws -> [String] {
            switch loggedQuery.replay {
            case let .search(tags, limit):
                return try db.run(
                    SearchNotesFTSTransaction(
                        match: .text(loggedQuery.text, keywords: keywords),
                        tags: tags,
                        limit: limit,
                        sessionId: loggedQuery.sessionId,
                        primingWindowMin: tuning.primingWindowMin,
                        primingAlpha: tuning.primingAlpha
                    )
                )
                    .map { hit in hit.id }

            case .related:
                let snapshot = try db.run(
                    BuildFramingSnapshotTransaction(
                        text: loggedQuery.text,
                        sessionId: loggedQuery.sessionId,
                        keywords: keywords,
                        entities: entities,
                        similarLimit: tuning.similarLimit,
                        expandHops: tuning.expandHops,
                        neighborFloor: tuning.neighborFloor,
                        siblingDiscount: tuning.siblingDiscount,
                        primingWindowMin: tuning.primingWindowMin,
                        primingAlpha: tuning.primingAlpha
                    )
                )

                return snapshot.similar.map { note in note.id }
                    + snapshot.linked.map { note in note.id }
                    + snapshot.vectorLinked.map { note in note.id }
            }
        }

        var diffs: [GenomeShadowResult.QueryDiff] = []
        var changed = 0

        for loggedQuery in logged {
            let baseline = try replayIds(db, RetrievalTuning(brain.genes), loggedQuery)
            let candidate = try replayIds(
                db,
                RetrievalTuning(brain.shadowing(gene: gene, value: value).genes),
                loggedQuery
            )

            if baseline != candidate {
                changed += 1

                if diffs.count < sampleDiffs {
                    let baselineIds = Set(baseline)
                    let candidateIds = Set(candidate)

                    diffs.append(
                        GenomeShadowResult.QueryDiff(
                            query: "\(loggedQuery.replay.command.rawValue): \(loggedQuery.text)",
                            baseline: baseline,
                            candidate: candidate,
                            entered: candidate.filter { id in !baselineIds.contains(id) },
                            dropped: baseline.filter { id in !candidateIds.contains(id) }
                        )
                    )
                }
            }
        }

        return GenomeShadowResult(
            gene: gene,
            baselineValue: baselineValue,
            candidateValue: value,
            queriesReplayed: logged.count,
            queriesChanged: changed,
            diffs: diffs
        )
    }

    // MARK: - Private
    // Catalog mapping over an explicit value snapshot — the list reports
    // committed state, so the genome value comes from the read rather than
    // from the process cache. Which value wins and what it is called is
    // Genes.resolve's answer, not a second copy of it.
    private func catalogRows(_ genes: Genes, values: [String: Double]) -> [GeneListRow] {
        Genes.catalog.map { gene in
            let resolved = genes.resolve(gene, stored: values[gene.id])

            return GeneListRow(
                id: gene.id,
                value: resolved.value,
                wildType: gene.wildType,
                min: gene.min,
                max: gene.max,
                mutable: gene.mutable,
                source: resolved.source,
                summary: gene.summary
            )
        }
    }
}
