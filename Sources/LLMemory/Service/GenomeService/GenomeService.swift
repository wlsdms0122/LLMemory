//
//  GenomeService.swift
//  LLMemory
//
//  Created by JSilver on 8/9/26.
//

import Foundation
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
    let keywords: any KeywordExtracting
    let entities: any EntityHinting

    // MARK: - Initializer
    init(
        storage: GRDBStorage,
        keywords: any KeywordExtracting,
        entities: any EntityHinting
    ) {
        self.storage = storage
        self.keywords = keywords
        self.entities = entities
    }

    // MARK: - Public
    // Maps the catalog against values fetched in this scope — no cache
    // mutation on the read path (read scopes read; only gated writers warm).
    // The connection gate stays: an uninitialized brain fails loud instead
    // of masquerading as wild-type.
    public func list() async throws -> [GeneListRow] {
        try await storage.read { scope in
            catalogRows(values: try scope.run(FetchGenomeValuesTransaction()))
        }
    }

    public func history(
        gene: String?,
        limit: Int
    ) async throws -> [GeneHistoryRow] {
        try await storage.read { scope in
            try history(scope, gene: gene, limit: limit)
        }
    }

    public func shadow(
        gene: String,
        value: Double,
        limit: Int,
        sampleDiffs: Int
    ) async throws -> GenomeShadowResult {
        try await storage.read { scope in
            try shadow(scope, gene: gene, value: value, limit: limit, sampleDiffs: sampleDiffs)
        }
    }

    // MARK: - Internal
    func history(
        _ scope: GRDBReadScope,
        gene: String?,
        limit: Int
    ) throws -> [GeneHistoryRow] {
        try scope.run(FetchGenomeEventsTransaction(geneId: gene, limit: limit))
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
        _ scope: GRDBReadScope,
        gene: String,
        value: Double,
        limit: Int,
        sampleDiffs: Int
    ) throws -> GenomeShadowResult {
        if let rejection = Genes.rejection(gene, value: value) { throw rejection }

        let baselineValue = Genes.double(gene)
        let logged = try scope.run(FetchLoggedRetrievalQueriesTransaction(limit: limit))

        func replayIds(
            _ loggedQuery: FetchLoggedRetrievalQueriesTransaction.LoggedQuery
        ) throws -> [String] {
            switch loggedQuery.replay {
            case let .search(tags, limit):
                return try scope.run(
                    SearchNotesFTSTransaction(
                        match: .text(loggedQuery.text, keywords: keywords),
                        tags: tags,
                        limit: limit,
                        sessionId: loggedQuery.sessionId
                    )
                )
                    .map { hit in hit.id }

            case .related:
                let snapshot = try scope.run(
                    BuildFramingSnapshotTransaction(
                        text: loggedQuery.text,
                        sessionId: loggedQuery.sessionId,
                        keywords: keywords,
                        entities: entities
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
            let baseline = try replayIds(loggedQuery)
            let candidate = try Genes.withCandidate(gene, value) { try replayIds(loggedQuery) }

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
    private func catalogRows(values: [String: Double]) -> [GeneListRow] {
        Genes.catalog.map { gene in
            let resolved = Genes.resolve(gene, stored: values[gene.id])

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
