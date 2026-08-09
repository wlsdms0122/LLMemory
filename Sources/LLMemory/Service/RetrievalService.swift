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
public enum RetrievalService {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Public
    public static func search(
        _ storage: GRDBStorage,
        query: String,
        axis: String?,
        limit: Int,
        expand: Int,
        cliSessionId: String,
        includeStale: Bool,
        excludeAxes: [String],
        raw: Bool
    ) async throws -> (rows: [Search.SearchRow], extra: [Links.ExpandedNote]) {
        let sessionId = Env.retrievalSession(cli: cliSessionId)
        let outcome = try await storage.read { scope in
            try search(
                scope,
                query: query,
                axis: axis,
                limit: limit,
                expand: expand,
                sessionId: sessionId,
                includeStale: includeStale,
                excludeAxes: excludeAxes.isEmpty ? nil : excludeAxes,
                raw: raw
            )
        }

        try await applyRecord(storage, outcome.record)

        return (outcome.rows, outcome.extra)
    }

    public static func related(
        _ storage: GRDBStorage,
        text: String,
        kind: String?,
        cliSessionId: String,
        includeBodies: Bool
    ) async throws -> Framing.RelatedResult {
        let sessionId = Env.retrievalSession(cli: cliSessionId)
        let outcome = try await storage.read { scope in
            try related(
                scope,
                text: text,
                kind: kind,
                sessionId: sessionId,
                includeBodies: includeBodies
            )
        }

        let degraded = try await applyRecord(storage, outcome.record)

        guard !degraded.isEmpty else { return outcome.result }

        var snapshot = outcome.result.snapshot
        snapshot.degraded.append(contentsOf: degraded)

        return Framing.RelatedResult(snapshot: snapshot, bodies: outcome.result.bodies)
    }

    public static func neighbors(
        _ storage: GRDBStorage,
        id: String,
        k: Int,
        cliSessionId: String = ""
    ) async throws -> [Candidates.NeighborScore] {
        let sessionId = Env.retrievalSession(cli: cliSessionId)
        let outcome = try await storage.read { scope in
            try neighbors(scope, id: id, k: k, sessionId: sessionId)
        }

        try await applyRecord(storage, outcome.record)

        return outcome.scores
    }

    public static func entity(
        _ storage: GRDBStorage,
        name: String?,
        limit: Int
    ) async throws -> [Reads.EntityHit] {
        try await storage.read { scope in
            try scope.run(LookupEntitiesTransaction(name: name, limit: limit))
        }
    }

    // MARK: - Internal
    static func search(
        _ scope: GRDBReadScope,
        query: String,
        axis: String? = nil,
        limit: Int = 5,
        expand: Int = 0,
        sessionId: String? = nil,
        includeStale: Bool = false,
        excludeAxes: [String]? = nil,
        sinceTs: Int? = nil,
        raw: Bool = false
    ) throws -> (rows: [Search.SearchRow], extra: [Links.ExpandedNote], record: RetrievalRecord) {
        let rows = try scope.run(
            SearchNotesFTSTransaction(
                query: query,
                axis: axis,
                limit: limit,
                includeStale: includeStale,
                excludeAxes: excludeAxes,
                sinceTs: sinceTs,
                sessionId: sessionId,
                raw: raw
            )
        )
        var extra: [Links.ExpandedNote] = []

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
        let payload: [(String, Any?)] = [
            ("query", trimmedQuery),
            ("axis", axis),
            ("limit", limit),
            ("include_stale", includeStale),
            ("exclude_axes", excludeAxes as Any?),
            ("since_ts", sinceTs as Any?),
            ("hit_ids", rows.map { row in row.id }),
            ("expand_ids", extra.map { note in note.id })
        ]
        let record = RetrievalRecord(
            sessionId: sessionId,
            activateIds: hitIds,
            strengthenPairs: cooccurrencePairs(hitIds),
            rebirthRanked: searchRanked(rows: rows, extra: extra),
            payloadJSON: Events.retrievalPayloadJSON(cmd: "search", payload: payload)
        )

        return (rows, extra, record)
    }

    static func snapshot(
        _ scope: GRDBReadScope,
        userInput: String,
        agentOutput: String,
        similarLimit: Int? = nil,
        expandHops: Int? = nil,
        linkKind: String? = nil,
        sessionId: String? = nil
    ) throws -> Framing.Snapshot {
        let similarLimit = similarLimit ?? Genes.int("related.similar_limit")
        let expandHops = expandHops ?? Genes.int("related.expand_hops")
        let text = "\(userInput)\n\(agentOutput)"
        let keywords = Framing.extractKeywords(text)
        let entityHints = NoteText.extractEntityHints(text)
        var similarNotes: [Framing.SimilarNote] = []
        var axes: [Framing.AxisRow] = []
        var topTagCounts: [(String, Int)] = []
        var cooccurrences: [(String, String, Int)] = []
        var vocabEntries: [String] = []
        var entityHits: [EntityHit] = []
        
        similarNotes = try scope.run(
            FetchSimilarNotesTransaction(
                keywords: keywords,
                limit: similarLimit,
                sessionId: sessionId
            )
        )

        let similarTagSet = Set(similarNotes.flatMap { note in note.tags })
        axes = try scope.run(FetchAxesInfoTransaction())
        topTagCounts = try scope.run(FetchTopTagsTransaction())
        cooccurrences = try scope.run(FetchTagCooccurrenceTransaction(tags: similarTagSet.sorted()))
        vocabEntries = try scope.run(FetchTagVocabTransaction())
        entityHits = try scope.run(FetchEntityHitsTransaction(entities: entityHints))
        
        var degraded: [String] = []
        var linked: [Links.ExpandedNote] = []
        
        if !similarNotes.isEmpty {
            do {
                linked = try scope.run(
                    ExpandLinksTransaction(
                        noteIds: similarNotes.map { note in note.id },
                        hops: expandHops,
                        kind: linkKind
                    )
                )
            } catch {
                degraded.append("linked: \(error)")
            }
        }
        
        var vectorLinked: [VectorHit] = []
        
        if !similarNotes.isEmpty {
            let already = Set(similarNotes.map { note in note.id })
                .union(linked.map { note in note.id })
            
            do {
                vectorLinked = try scope.run(
                    ExpandByVectorsTransaction(
                        seedIds: similarNotes.map { note in note.id },
                        limit: similarLimit,
                        excludeIds: already
                    )
                )
            } catch {
                degraded.append("vector_linked: \(error)")
            }
        }
        
        return Framing.Snapshot(
            keywords: keywords,
            axes: axes,
            similar: similarNotes,
            linked: linked,
            vectorLinked: vectorLinked,
            topTags: topTagCounts,
            cooccur: cooccurrences,
            vocab: vocabEntries,
            entityHints: entityHints,
            entityHits: entityHits,
            degraded: degraded
        )
    }

    static func related(
        _ scope: GRDBReadScope,
        text: String,
        kind: String?,
        sessionId: String?,
        includeBodies: Bool
    ) throws -> (result: Framing.RelatedResult, record: RetrievalRecord) {
        let snapshot = try snapshot(
            scope,
            userInput: text,
            agentOutput: "",
            linkKind: kind,
            sessionId: sessionId
        )

        var bodies: [String: String] = [:]

        if includeBodies {
            for note in snapshot.similar {
                let path = Paths.brainRoot.appendingPathComponent(note.path)

                if let body = try? String(contentsOf: path, encoding: .utf8) {
                    bodies[note.id] = body
                }
            }
        }

        let record = RetrievalRecord(
            sessionId: sessionId,
            rebirthRanked: relatedRanked(snapshot: snapshot),
            payloadJSON: Events.retrievalPayloadJSON(cmd: "related", payload: [
                ("text", String(text.prefix(200))),
                ("hit_ids", snapshot.similar.map { note in note.id }),
                ("expand_ids", snapshot.linked.map { note in note.id })
            ])
        )

        return (Framing.RelatedResult(snapshot: snapshot, bodies: bodies), record)
    }

    static func neighbors(
        _ scope: GRDBReadScope,
        id: String,
        k: Int,
        sessionId: String? = nil
    ) throws -> (scores: [Candidates.NeighborScore], record: RetrievalRecord?) {
        let scores = try scope.run(FetchNeighborScoresTransaction(noteId: id, k: k))
        let record: RetrievalRecord? = scores.isEmpty ? nil : .init(
            sessionId: sessionId,
            payloadJSON: Events.retrievalPayloadJSON(cmd: "neighbors", payload: [
                ("anchor", id),
                ("hit_ids", scores.map { score in score.id })
            ])
        )

        return (scores, record)
    }

    // The one place read-derived side effects get applied — surfaces never
    // juggle the record by hand. Throws when the mandatory state transition
    // (activation) fails; advisory failures come back as degraded notes.
    @discardableResult
    static func applyRecord(
        _ storage: GRDBStorage,
        _ record: RetrievalRecord?
    ) async throws -> [String] {
        guard let record else { return [] }

        return try await storage.run { scope in
            try scope.run(RecordRetrievalTransaction(record))
        }
    }

    // MARK: - Private
    // Pure derivations of the retrieval side effects — applied later by
    // RecordRetrievalTransaction on the write path.
    private static func cooccurrencePairs(_ ids: [String]) -> [RetrievalRecord.Pair] {
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

    private static func searchRanked(
        rows: [Search.SearchRow],
        extra: [Links.ExpandedNote]
    ) -> [RetrievalRecord.Ranked] {
        let boost = Genes.double("rebirth.search_boost")
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

    private static func relatedRanked(snapshot: Framing.Snapshot) -> [RetrievalRecord.Ranked] {
        let boost = Genes.double("rebirth.related_boost")
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
