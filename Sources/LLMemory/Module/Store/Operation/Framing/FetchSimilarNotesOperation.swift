//
//  FetchSimilarNotesOperation.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct FetchSimilarNotesOperation: GRDBReadOperation {
    // MARK: - Property
    let keywords: [String]
    let limit: Int
    let includeStale: Bool
    let sessionId: SessionId?
    let primingWindowMin: Int
    let primingAlpha: Double

    // MARK: - Initializer
    init(
        keywords: [String],
        limit: Int,
        includeStale: Bool = false,
        sessionId: SessionId? = nil,
        primingWindowMin: Int,
        primingAlpha: Double
    ) {
        self.keywords = keywords
        self.limit = limit
        self.includeStale = includeStale
        self.sessionId = sessionId
        self.primingWindowMin = primingWindowMin
        self.primingAlpha = primingAlpha
    }

    // MARK: - Public
    func execute(_ db: Database) throws -> [SimilarNote] {
        guard let expression = FTSMatch.cues(keywords).expression else { return [] }

        var sql = """
                SELECT n.id, n.title, n.summary,
                       (SELECT group_concat(tag, ',') FROM tags WHERE note_id = n.id) AS tags,
                       f.section AS section, MIN(rank) AS best_rank
                FROM notes_fts f JOIN notes n ON n.id = f.id
                WHERE notes_fts MATCH ?
                """
        var arguments: [DatabaseValueConvertible?] = [expression]

        if !includeStale {
            sql += " AND \(Policy.fresh())"
        }

        let now = Int(Date().timeIntervalSince1970)
        let prior = TagPriorRerank.prior(
            db,
            sessionId: sessionId,
            windowMin: primingWindowMin,
            now: now
        )

        sql += SearchRow.aggregationSQL
        arguments.append(TagPriorRerank.poolSize(limit: limit, needsRerank: !prior.isEmpty))

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
                tags: tags,
                section: section
            )
        }

        return TagPriorRerank.apply(
            pool,
            prior: prior,
            alpha: primingAlpha,
            limit: limit
        ) { note in note.tags }
    }

    // MARK: - Private
}
