//
//  TagPriorRerank.swift
//  LLMemory
//
//  Created by JSilver on 8/16/26.
//

import Foundation
import GRDB

// Reordering a result pool by what the session has been reading lately. The
// three steps belong together because each is meaningless without the others:
// there is no reason to over-fetch unless a rerank is coming, and no rerank
// unless a prior was found.
enum TagPriorRerank {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Public
    // Nothing to reorder by when there is no session to have a history, and
    // nothing when reading it failed either — a ranking hint that could not be
    // computed is not a reason to refuse the query it was going to improve.
    static func prior(
        _ db: Database,
        sessionId: SessionId?,
        windowMin: Int,
        now: Int
    ) -> [String: Double] {
        guard let sessionId else { return [:] }

        return (try? ComputeTagPriorTransaction(
            sessionId: sessionId,
            windowSec: windowMin * 60,
            now: now
        )
            .perform(db)) ?? [:]
    }

    // A rerank can only promote what was fetched, so the pool has to be wider
    // than the answer — and only when there is something to reorder by.
    static func poolSize(limit: Int, needsRerank: Bool) -> Int {
        needsRerank ? limit + min(limit * 2, 30) : limit
    }

    // The boost takes the item's *strongest* reinstated tag rather than the
    // sum: a note that carries five tags is not five times more primed, and
    // summing would make tag count itself a ranking signal.
    static func apply<T>(
        _ pool: [T],
        prior: [String: Double],
        alpha: Double,
        limit: Int,
        tagsOf: (T) -> [String]
    ) -> [T] {
        guard !prior.isEmpty else { return Array(pool.prefix(limit)) }

        let poolCount = Double(pool.count)
        let scored: [(index: Int, score: Double, item: T)] = pool.enumerated()
            .map { index, item in
                let rankScore = poolCount - Double(index)
                let warmth = tagsOf(item).compactMap { tag in prior[tag] }.max() ?? 0
                let tagBoost = alpha * warmth * poolCount

                return (index, rankScore + tagBoost, item)
            }

        return scored
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }

                return lhs.index < rhs.index
            }
            .prefix(limit)
            .map { scoredItem in scoredItem.item }
    }

    // MARK: - Private
}
