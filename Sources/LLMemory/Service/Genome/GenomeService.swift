//
//  GenomeService.swift
//  LLMemory
//
//  Created by JSilver on 8/9/26.
//

import Foundation

// Genome-domain service — the observation surfaces: the catalog with this
// brain's values, the provenance of every mutation, and offline reranking
// under a candidate value.
//
// It does not own the plasticity rules. What a gene admits is the catalog's
// (Genes.rejection), and writing a value is a transaction — both live in the
// module, where the callers that need them already are.
public struct GenomeService: GenomeServiceable {
    // MARK: - Property
    let storage: any GRDBStorable
    let brain: BrainContext
    let keywords: any KeywordExtracting
    let entities: any EntityHinting

    // MARK: - Initializer
    init(
        storage: any GRDBStorable,
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
    // Maps the catalog against values fetched in this run — no cache mutation on
    // the read path (reads read; only gated writers warm).
    public func list() async throws -> [GeneListRow] {
        catalogRows(brain.genes, values: try await storage.run(FetchGenomeValuesTransaction()))
    }

    public func history(
        gene: String?,
        limit: Int
    ) async throws -> [GeneHistoryRow] {
        try await storage.run(FetchGenomeEventsTransaction(geneId: gene, limit: limit))
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

    // Offline reranking — the replay runs against the current corpus under a
    // candidate gene value. The candidate never reaches the brain's cache: it is
    // resolved into the numbers the replay takes, so a concurrent reader of this
    // brain cannot see it and nothing has to be put back afterwards.
    public func shadow(
        gene: String,
        value: Double,
        limit: Int,
        sampleDiffs: Int
    ) async throws -> GenomeShadowResult {
        if let rejection = Genes.rejection(gene, value: value) { throw rejection }

        let outcome = try await storage.run(
            ReplayRetrievalQueriesTransaction(
                baseline: RetrievalTuning(brain.genes),
                candidate: RetrievalTuning(brain.shadowing(gene: gene, value: value).genes),
                limit: limit,
                sampleDivergences: sampleDiffs,
                keywords: keywords,
                entities: entities
            )
        )

        return GenomeShadowResult(
            gene: gene,
            baselineValue: brain.genes.double(gene),
            candidateValue: value,
            queriesReplayed: outcome.replayed,
            queriesChanged: outcome.changed,
            diffs: outcome.divergences.map { divergence in
                let baseline = Set(divergence.baseline)
                let candidate = Set(divergence.candidate)

                return GenomeShadowResult.QueryDiff(
                    query: divergence.query,
                    baseline: divergence.baseline,
                    candidate: divergence.candidate,
                    entered: divergence.candidate.filter { id in !baseline.contains(id) },
                    dropped: divergence.baseline.filter { id in !candidate.contains(id) }
                )
            }
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
