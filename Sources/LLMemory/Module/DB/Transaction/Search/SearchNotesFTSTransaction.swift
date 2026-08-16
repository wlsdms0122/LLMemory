//
//  SearchNotesFTSTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct SearchNotesFTSTransaction: GRDBBrainReadTransaction {
    // MARK: - Property
    let match: FTSMatch
    let tags: [String]
    let limit: Int
    let includeStale: Bool
    let excludeTags: [String]?
    let sinceTs: Int?
    let sessionId: SessionId?

    // MARK: - Initializer
    init(
        match: FTSMatch,
        tags: [String] = [],
        limit: Int = 5,
        includeStale: Bool = false,
        excludeTags: [String]? = nil,
        sinceTs: Int? = nil,
        sessionId: SessionId? = nil
    ) {
        self.match = match
        self.tags = tags
        self.limit = limit
        self.includeStale = includeStale
        self.excludeTags = excludeTags
        self.sinceTs = sinceTs
        self.sessionId = sessionId
    }

    // MARK: - Public
    func perform(_ db: Database, _ brain: BrainContext) throws -> [SearchRow] {
        guard let expression = match.expression else { return [] }

        var sql = SearchRow.projectionSQL + """
             FROM notes_fts f JOIN notes n ON n.id = f.id
             LEFT JOIN note_usage u ON u.note_id = n.id
             WHERE notes_fts MATCH ?
            """
        var arguments: [DatabaseValueConvertible?] = [expression]

        for (clause, tagArguments) in [
            try TagFilter.clause(db, tags: tags),
            try TagFilter.clause(db, tags: excludeTags ?? [], negated: true)
        ] where !clause.isEmpty {
            sql += " AND \(clause)"
            arguments.append(contentsOf: tagArguments)
        }

        if let sinceTs {
            sql += " AND COALESCE(u.last_retrieved_at, 0) >= ?"
            arguments.append(sinceTs)
        }

        if !includeStale {
            sql += " AND \(Policy.fresh())"
        }

        let now = Int(Date().timeIntervalSince1970)
        let prior = TagPriorRerank.prior(
            db,
            sessionId: sessionId,
            windowMin: brain.genes.int("priming.window_min"),
            now: now
        )

        sql += SearchRow.aggregationSQL
        arguments.append(TagPriorRerank.poolSize(limit: limit, needsRerank: !prior.isEmpty))

        let rows: [Row]

        do {
            rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(arguments))
        } catch {
            throw match.rejection(expression) ?? error
        }

        return TagPriorRerank.apply(
            rows.map { row in SearchRow(row, brain.paths) },
            prior: prior,
            alpha: brain.genes.double("priming.alpha"),
            limit: limit
        ) { row in row.tags }
    }

    // MARK: - Private
}
