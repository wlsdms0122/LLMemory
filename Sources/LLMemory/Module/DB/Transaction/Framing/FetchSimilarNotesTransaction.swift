//
//  FetchSimilarNotesTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct FetchSimilarNotesTransaction: GRDBReadTransaction {
    // MARK: - Property
    let keywords: [String]
    let limit: Int
    let includeStale: Bool
    let sessionId: String?

    // MARK: - Initializer
    init(keywords: [String], limit: Int, includeStale: Bool = false, sessionId: String? = nil) {
        self.keywords = keywords
        self.limit = limit
        self.includeStale = includeStale
        self.sessionId = sessionId
    }

    // MARK: - Public
    func perform(_ db: Database) throws -> [SimilarNote] {
        let matchExpr = Framing.ftsQuery(keywords)

        if matchExpr.isEmpty { return [] }

        var sql = """
                SELECT n.id, n.title, n.summary,
                       (SELECT group_concat(tag, ',') FROM tags WHERE note_id = n.id) AS tags,
                       f.section AS section, MIN(rank) AS best_rank
                FROM notes_fts f JOIN notes n ON n.id = f.id
                WHERE notes_fts MATCH ?
                """
        var arguments: [DatabaseValueConvertible?] = [matchExpr]

        if !includeStale {
            sql += " AND \(Policy.fresh())"
        }

        let now = Int(Date().timeIntervalSince1970)
        let prior: [String: Double]

        if let sessionId, !sessionId.isEmpty {
            let windowMin = Genes.int("priming.window_min")
            prior = (try? ComputeTagPriorTransaction(
                sessionId: sessionId,
                windowSec: windowMin * 60,
                now: now
            )
                .perform(db)) ?? [:]
        } else {
            prior = [:]
        }

        let needsRerank = !prior.isEmpty
        let fetchLimit = Search.fetchPoolSize(limit: limit, needsRerank: needsRerank)
        sql += Search.noteAggregationSQL
        arguments.append(fetchLimit)

        let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(arguments))
        let pool: [SimilarNote] = rows.map { row in
            let tagsCSV = row["tags"] as String? ?? ""
            let tags = tagsCSV.isEmpty ? [] : tagsCSV.split(separator: ",").map(String.init)
            let section = (row["section"] as String?).flatMap { value in
                value.isEmpty ? nil : value
            }

            return SimilarNote(
                id: row["id"],
                title: row["title"],
                summary: row["summary"] as String?,
                path: Paths.relativeFile(forId: row["id"] as String),
                tags: tags,
                section: section
            )
        }

        if !needsRerank { return pool }

        return Search.rerank(pool, prior: prior, limit: limit) { note in note.tags }
    }

    // MARK: - Private
}
