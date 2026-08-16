//
//  RetrievalService.swift
//  LLMemory
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import Storage

// Retrieval-domain service — the associative surfaces (search, related,
// neighbors, entity) and the side-effect record they derive. Reads run in a
// read scope; the record is applied afterwards in its own write scope, so
// retrieval must not fail because its trace could not be written.
public struct RetrievalService: RetrievalServiceable {
    // MARK: - Property
    let storage: GRDBStorage
    let brain: BrainContext
    let keywords: any KeywordExtracting
    let entities: any EntityHinting

    private let detector = CandidateDetector()

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
    public func search(
        query: String,
        tags: [String],
        limit: Int,
        expand: Int,
        sessionId: SessionId?,
        includeStale: Bool,
        excludeTags: [String],
        raw: Bool
    ) async throws -> (rows: [SearchRow], extra: [ExpandedNote]) {
        let outcome = try await storage.read { scope in
            try search(
                scope,
                query: query,
                tags: tags,
                limit: limit,
                expand: expand,
                sessionId: sessionId,
                includeStale: includeStale,
                excludeTags: excludeTags.isEmpty ? nil : excludeTags,
                raw: raw
            )
        }

        try await applyRecord(outcome.record)

        return (outcome.rows, outcome.extra)
    }

    public func related(
        text: String,
        kind: LinkKind?,
        sessionId: SessionId?,
        includeBodies: Bool
    ) async throws -> RelatedResult {
        let outcome = try await storage.read { scope in
            try related(
                scope,
                text: text,
                kind: kind,
                sessionId: sessionId,
                includeBodies: includeBodies
            )
        }

        let degraded = try await applyRecord(outcome.record)

        guard !degraded.isEmpty else { return outcome.result }

        var snapshot = outcome.result.snapshot
        snapshot.degraded.append(contentsOf: degraded)

        return RelatedResult(snapshot: snapshot, bodies: outcome.result.bodies)
    }

    public func neighbors(
        id: String,
        k: Int,
        sessionId: SessionId?
    ) async throws -> [NeighborScore] {
        let outcome = try await storage.read { scope in
            try neighbors(scope, id: id, k: k, sessionId: sessionId)
        }

        try await applyRecord(outcome.record)

        return outcome.scores
    }

    public func entity(
        name: String?,
        limit: Int
    ) async throws -> [EntityHit] {
        try await storage.read { scope in
            try scope.run(LookupEntitiesTransaction(name: name, limit: limit))
        }
    }

    // MARK: - Internal
    func search(
        _ scope: GRDBReadScope,
        query: String,
        tags: [String] = [],
        limit: Int = 5,
        expand: Int = 0,
        sessionId: SessionId? = nil,
        includeStale: Bool = false,
        excludeTags: [String]? = nil,
        sinceTs: Int? = nil,
        raw: Bool = false
    ) throws -> (rows: [SearchRow], extra: [ExpandedNote], record: RetrievalRecord) {
        let rows = try scope.run(
            SearchNotesFTSTransaction(
                match: raw ? .raw(query) : .text(query, keywords: keywords),
                tags: tags,
                limit: limit,
                includeStale: includeStale,
                excludeTags: excludeTags,
                sinceTs: sinceTs,
                sessionId: sessionId
            )
        )
        var extra: [ExpandedNote] = []

        if expand > 0 {
            extra = (try? scope.run(
                ExpandLinksTransaction(
                    noteIds: rows.map { row in row.id },
                    hops: 1,
                    limit: expand
                )
            )) ?? []
        }

        let hitIds = rows.map { row in row.id } + extra.map { note in note.id }
        let trimmedQuery = String(query.prefix(200))
        let payload: [String: JSONValue?] = [
            "query": .string(trimmedQuery),
            "tags": JSONValue(tags),
            "limit": .integer(limit),
            "include_stale": .bool(includeStale),
            "exclude_tags": excludeTags.map { tags in JSONValue(tags) },
            "since_ts": sinceTs.map { timestamp in .integer(timestamp) },
            "hit_ids": JSONValue(rows.map { row in row.id }),
            "expand_ids": JSONValue(extra.map { note in note.id })
        ]
        let record = RetrievalRecord(
            sessionId: sessionId,
            activateIds: hitIds,
            strengthenPairs: cooccurrencePairs(hitIds),
            rebirthRanked: searchRanked(brain.genes, rows: rows, extra: extra),
            payload: EventPayload(command: .search, payload)
        )

        return (rows, extra, record)
    }

    func related(
        _ scope: GRDBReadScope,
        text: String,
        kind: LinkKind?,
        sessionId: SessionId?,
        includeBodies: Bool
    ) throws -> (result: RelatedResult, record: RetrievalRecord) {
        let snapshot = try scope.run(
            BuildFramingSnapshotTransaction(
                text: text,
                linkKind: kind,
                sessionId: sessionId,
                keywords: keywords,
                entities: entities
            )
        )

        var bodies: [String: String] = [:]

        if includeBodies {
            for note in snapshot.similar {
                let path = brain.layout.brainRoot.appendingPathComponent(note.path)

                if let body = try? String(contentsOf: path, encoding: .utf8) {
                    bodies[note.id] = body
                }
            }
        }

        let record = RetrievalRecord(
            sessionId: sessionId,
            rebirthRanked: relatedRanked(brain.genes, snapshot: snapshot),
            payload: EventPayload(command: .related, [
                "text": .string(String(text.prefix(200))),
                "hit_ids": JSONValue(snapshot.similar.map { note in note.id }),
                "expand_ids": JSONValue(snapshot.linked.map { note in note.id })
            ])
        )

        return (RelatedResult(snapshot: snapshot, bodies: bodies), record)
    }

    func neighbors(
        _ scope: GRDBReadScope,
        id: String,
        k: Int,
        sessionId: SessionId? = nil
    ) throws -> (scores: [NeighborScore], record: RetrievalRecord?) {
        let scores = try detector.neighbors(scope, noteId: id, k: k)
        let record: RetrievalRecord? = scores.isEmpty ? nil : .init(
            sessionId: sessionId,
            payload: EventPayload(command: .neighbors, [
                "anchor": .string(id),
                "hit_ids": JSONValue(scores.map { score in score.id })
            ])
        )

        return (scores, record)
    }

    // The one place read-derived side effects get applied — surfaces never
    // juggle the record by hand. Throws when the mandatory state transition
    // (activation) fails; advisory failures come back as degraded notes.
    @discardableResult
    func applyRecord(
        _ record: RetrievalRecord?
    ) async throws -> [String] {
        guard let record else { return [] }

        return try await storage.run { scope in
            try scope.run(
                RecordRetrievalTransaction(
                    record,
                    strengthenStep: brain.genes.double("links.strengthen_step"),
                    rebirthFactor: brain.genes.double("rebirth.default_factor")
                )
            )
        }
    }

    // MARK: - Private
    // Pure derivations of the retrieval side effects — applied later by
    // RecordRetrievalTransaction on the write path.
    private func cooccurrencePairs(_ ids: [String]) -> [RetrievalRecord.Pair] {
        var seen = Set<String>()
        var unique: [String] = []

        for id in ids where !id.isEmpty && !seen.contains(id) {
            seen.insert(id)
            unique.append(id)
        }

        if unique.count < 2 || unique.count > 8 { return [] }

        var pairs: [RetrievalRecord.Pair] = []

        for left in 0..<unique.count {
            for right in (left + 1)..<unique.count {
                pairs.append(RetrievalRecord.Pair(unique[left], unique[right]))
            }
        }

        return pairs
    }

    private func searchRanked(
        _ genes: Genes,
        rows: [SearchRow],
        extra: [ExpandedNote]
    ) -> [RetrievalRecord.Ranked] {
        let boost = genes.double("rebirth.search_boost")
        var ranked: [RetrievalRecord.Ranked] = []

        for (index, row) in rows.enumerated() {
            ranked.append(RetrievalRecord.Ranked(row.id, 1.0 + boost / Double(index + 1)))
        }

        let base = rows.count

        for (index, note) in extra.enumerated() {
            ranked.append(RetrievalRecord.Ranked(note.id, 1.0 + boost / Double(base + index + 1)))
        }

        return ranked
    }

    private func relatedRanked(_ genes: Genes, snapshot: FramingSnapshot) -> [RetrievalRecord.Ranked] {
        let boost = genes.double("rebirth.related_boost")
        var ranked: [RetrievalRecord.Ranked] = []

        for (index, note) in snapshot.similar.enumerated() {
            ranked.append(RetrievalRecord.Ranked(note.id, 1.0 + boost / Double(index + 1)))
        }

        let baseRank = snapshot.similar.count

        for (index, note) in snapshot.linked.enumerated() {
            ranked.append(RetrievalRecord.Ranked(note.id, 1.0 + boost / Double(baseRank + index + 1)))
        }

        return ranked
    }
}
