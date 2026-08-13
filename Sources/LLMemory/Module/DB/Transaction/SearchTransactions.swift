//
//  SearchTransactions.swift
//  LLMemory
//
//  Created by JSilver on 8/7/26.
//

import Foundation
import GRDB

// One FTS hit — a struct rather than a tuple so surfaces can encode it
// without mirroring (extra carries the shared-term count on expanded rows).
public struct SearchRow: Sendable {
    // MARK: - Property
    public let path: String
    public let axis: String
    public let id: String
    public let title: String
    public let summary: String?
    public let tagsCSV: String?
    public let isStale: Bool
    public let section: String?
    public let extra: Int?
    
    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}

public enum Search {
    enum SearchError: LocalizedError {
        case invalidRawQuery(String)
        
        var errorDescription: String? {
            switch self {
            case .invalidRawQuery(let query):
                return "invalid FTS5 expression (--raw): \(query) — check quotes/operators (see `query search --help`)"
            }
        }
    }
    
    // MARK: - Property
    static let noteAggregationSQL = " GROUP BY n.id ORDER BY best_rank, n.id LIMIT ?"
    
    static let rowSQL = """
        SELECT n.path, n.axis, n.id, n.title, n.summary,
               (SELECT group_concat(tag, ',') FROM tags WHERE note_id = n.id) AS tags,
               (COALESCE(n.stale, 0) OR COALESCE((SELECT source_stale FROM note_source WHERE note_id = n.id), 0)) AS is_stale,
               f.section AS section, MIN(rank) AS best_rank
        """
    
    // MARK: - Initializer
    // MARK: - Public
    static func fetchPoolSize(limit: Int, needsRerank: Bool) -> Int {
        needsRerank ? limit + min(limit * 2, 30) : limit
    }
    
    static func ftsMatchExpr(_ query: String, raw: Bool) -> String? {
        if raw {
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            
            return trimmed.isEmpty ? nil : trimmed
        }
        
        let parts = Framing.extractKeywords(query)
            .map { keyword in "\"\(keyword.replacingOccurrences(of: "\"", with: ""))\"" }
        
        return parts.isEmpty ? nil : parts.joined(separator: " OR ")
    }
    

    
    // The boost takes the item's *strongest* reinstated tag rather than the sum:
    // a note that carries five tags is not five times more primed, and summing
    // would make tag count itself a ranking signal.
    static func rerank<T>(
        _ pool: [T],
        prior: [String: Double],
        limit: Int,
        tagsOf: (T) -> [String]
    ) -> [T] {
        let alpha = Genes.double("priming.alpha")
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
    static func staleClause(_ includeStale: Bool) -> String {
        includeStale ? "" : " AND \(Policy.fresh())"
    }
    
    static func fetchRows(
        _ db: Database,
        sql: String,
        arguments: [DatabaseValueConvertible?]
    ) throws -> [SearchRow] {
        let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(arguments))
        
        return rows.map { row in rowToSearchRow(row, hasExtra: false) }
    }
    
    private static func rowToSearchRow(_ row: Row, hasExtra: Bool) -> SearchRow {
        let section = (row["section"] as String?).flatMap { value in value.isEmpty ? nil : value }
        
        return SearchRow(
            path: row["path"],
            axis: row["axis"],
            id: row["id"],
            title: row["title"],
            summary: row["summary"] as String?,
            tagsCSV: row["tags"] as String?,
            isStale: (row["is_stale"] as Int? ?? 0) != 0,
            section: section,
            extra: hasExtra ? (row["shared"] as Int?) : nil
        )
    }
}

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

    // MARK: - Initializer
    init(
        query: String,
        tags: [String] = [],
        limit: Int = 5,
        includeStale: Bool = false,
        excludeTags: [String]? = nil,
        sinceTs: Int? = nil,
        sessionId: String? = nil,
        raw: Bool = false
    ) {
        self.query = query
        self.tags = tags
        self.limit = limit
        self.includeStale = includeStale
        self.excludeTags = excludeTags
        self.sinceTs = sinceTs
        self.sessionId = sessionId
        self.raw = raw
    }

    // MARK: - Public
    func perform(_ db: Database) throws -> [SearchRow] {
        guard let matchExpr = Search.ftsMatchExpr(query, raw: raw) else { return [] }
        
        var sql = Search.rowSQL + """
             FROM notes_fts f JOIN notes n ON n.id = f.id
             LEFT JOIN note_usage u ON u.note_id = n.id
             WHERE notes_fts MATCH ?
            """
        var arguments: [DatabaseValueConvertible?] = [matchExpr]
        
        // Aliases exist so a caller may spell a tag either way — resolve before matching,
        // since only the canonical spelling is stored on the note.
        for tag in tags {
            sql += " AND EXISTS (SELECT 1 FROM tags t WHERE t.note_id = n.id AND t.tag = ?)"
            arguments.append(try CanonicalizeTagTransaction(tag: tag).perform(db))
        }

        if let excludeTags, !excludeTags.isEmpty {
            let placeholders = Array(repeating: "?", count: excludeTags.count).joined(separator: ",")
            sql += " AND NOT EXISTS (SELECT 1 FROM tags t WHERE t.note_id = n.id"
                + " AND t.tag IN (\(placeholders)))"
            arguments.append(contentsOf: try excludeTags.map { tag in
                try CanonicalizeTagTransaction(tag: tag).perform(db)
            })
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
