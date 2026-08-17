//
//  ReplayRetrievalQueriesTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/17/26.
//

import Foundation
import GRDB

// Replays the logged retrieval queries twice — once under each set of numbers —
// and reports where the two rankings part.
//
// The two tunings arrive as values rather than as a brain to read them from: a
// replay has to say which numbers it ran with, and a query that re-derived them
// mid-flight could not. Which brain, and which gene, produced them is the
// caller's business.
struct ReplayRetrievalQueriesTransaction: GRDBReadTransaction {
    struct Divergence {
        // MARK: - Property
        let query: String
        let baseline: [String]
        let candidate: [String]

        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }

    struct Outcome {
        // MARK: - Property
        let replayed: Int
        let changed: Int
        let divergences: [Divergence]

        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }

    // MARK: - Property
    let baseline: RetrievalTuning
    let candidate: RetrievalTuning
    let limit: Int
    let sampleDivergences: Int
    let keywords: any KeywordExtracting
    let entities: any EntityHinting

    // MARK: - Initializer
    init(
        baseline: RetrievalTuning,
        candidate: RetrievalTuning,
        limit: Int,
        sampleDivergences: Int,
        keywords: any KeywordExtracting,
        entities: any EntityHinting
    ) {
        self.baseline = baseline
        self.candidate = candidate
        self.limit = limit
        self.sampleDivergences = sampleDivergences
        self.keywords = keywords
        self.entities = entities
    }

    // MARK: - Public
    func perform(_ db: Database) throws -> Outcome {
        let logged = try db.run(FetchLoggedRetrievalQueriesTransaction(limit: limit))

        var divergences: [Divergence] = []
        var changed = 0

        for query in logged {
            let baselineIds = try replay(db, query, tuning: baseline)
            let candidateIds = try replay(db, query, tuning: candidate)

            guard baselineIds != candidateIds else { continue }

            changed += 1

            if divergences.count < sampleDivergences {
                divergences.append(
                    Divergence(
                        query: "\(query.replay.command.rawValue): \(query.text)",
                        baseline: baselineIds,
                        candidate: candidateIds
                    )
                )
            }
        }

        return Outcome(replayed: logged.count, changed: changed, divergences: divergences)
    }

    // MARK: - Private
    private func replay(
        _ db: Database,
        _ query: FetchLoggedRetrievalQueriesTransaction.LoggedQuery,
        tuning: RetrievalTuning
    ) throws -> [String] {
        switch query.replay {
        case let .search(tags, limit):
            return try db.run(
                SearchNotesFTSTransaction(
                    match: .text(query.text, keywords: keywords),
                    tags: tags,
                    limit: limit,
                    sessionId: query.sessionId,
                    primingWindowMin: tuning.primingWindowMin,
                    primingAlpha: tuning.primingAlpha
                )
            )
                .map { hit in hit.id }

        case .related:
            let snapshot = try db.run(
                BuildFramingSnapshotTransaction(
                    text: query.text,
                    sessionId: query.sessionId,
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
}
