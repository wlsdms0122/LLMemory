//
//  SearchNotesFTSTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct SearchNotesFTSTransaction: GRDBReadTransaction {
    // MARK: - Property
    let query: String
    let tags: [String]
    let limit: Int
    let includeStale: Bool
    let excludeTags: [String]?
    let sinceTs: Int?
    let sessionId: String?
    let raw: Bool
    let keywords: any KeywordExtracting


    // MARK: - Initializer
    init(
        query: String,
        tags: [String] = [],
        limit: Int = 5,
        includeStale: Bool = false,
        excludeTags: [String]? = nil,
        sinceTs: Int? = nil,
        sessionId: String? = nil,
        raw: Bool = false,
        keywords: any KeywordExtracting
    ) {
        self.query = query
        self.tags = tags
        self.limit = limit
        self.includeStale = includeStale
        self.excludeTags = excludeTags
        self.sinceTs = sinceTs
        self.sessionId = sessionId
        self.raw = raw
        self.keywords = keywords
    }

    // MARK: - Public
    func perform(_ db: Database) throws -> [SearchRow] {
        guard let matchExpr = Search.ftsMatchExpr(query, raw: raw, keywords: keywords) else { return [] }
        
        var sql = Search.rowSQL + """
             FROM notes_fts f JOIN notes n ON n.id = f.id
             LEFT JOIN note_usage u ON u.note_id = n.id
             WHERE notes_fts MATCH ?
            """
        var arguments: [DatabaseValueConvertible?] = [matchExpr]
        
        for (clause, tagArguments) in [
            try Search.tagClause(db, tags: tags),
            try Search.tagClause(db, tags: excludeTags ?? [], negated: true)
        ] where !clause.isEmpty {
            sql += " AND \(clause)"
            arguments.append(contentsOf: tagArguments)
        }
        
        let now = Int(Date().timeIntervalSince1970)
        
        if let sinceTs {
            sql += " AND COALESCE(u.last_retrieved_at, 0) >= ?"
            arguments.append(sinceTs)
        }
        
        sql += Search.staleClause(includeStale)
        
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
        
        do {
            arguments.append(fetchLimit)
            
            let rawRows: [SearchRow]
            do {
                rawRows = try Search.fetchRows(db, sql: sql, arguments: arguments)
            } catch {
                if raw { throw Search.SearchError.invalidRawQuery(matchExpr) }
                
                throw error
            }
            
            if !needsRerank {
                return Array(rawRows.prefix(limit))
            }
            
            return Search.rerank(rawRows, prior: prior, limit: limit) { row in
                (row.tagsCSV ?? "").split(separator: ",").map(String.init)
            }
        }
    }

    // MARK: - Private
}
