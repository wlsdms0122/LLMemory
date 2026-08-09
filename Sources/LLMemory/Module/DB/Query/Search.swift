//
//  Search.swift
//  LLMemory
//
//  Created by JSilver on 8/7/26.
//

import Foundation
import GRDB

public enum Search {
    public typealias SearchRow = (
        path: String,
        axis: String,
        id: String,
        title: String,
        summary: String?,
        tagsCSV: String?,
        isStale: Bool,
        section: String?,
        extra: Int?
    )
    
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
    
    private static let rowSQL = """
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
    
    static func fts(
        _ db: Database,
        query: String,
        axis: String? = nil,
        limit: Int = 5,
        includeStale: Bool = false,
        excludeAxes: [String]? = nil,
        sinceTs: Int? = nil,
        sessionId: String? = nil,
        raw: Bool = false
    ) throws -> [SearchRow] {
        guard let matchExpr = ftsMatchExpr(query, raw: raw) else { return [] }
        
        var sql = rowSQL + """
             FROM notes_fts f JOIN notes n ON n.id = f.id
             LEFT JOIN note_usage u ON u.note_id = n.id
             WHERE notes_fts MATCH ?
            """
        var arguments: [DatabaseValueConvertible?] = [matchExpr]
        
        if let axis {
            sql += " AND n.axis = ?"
            arguments.append(axis)
        }
        
        if let excludeAxes, !excludeAxes.isEmpty {
            let placeholders = Array(repeating: "?", count: excludeAxes.count).joined(separator: ",")
            sql += " AND n.axis NOT IN (\(placeholders))"
            arguments.append(contentsOf: excludeAxes)
        }
        
        let now = Int(Date().timeIntervalSince1970)
        
        if let sinceTs {
            sql += " AND COALESCE(u.last_retrieved_at, 0) >= ?"
            arguments.append(sinceTs)
        }
        
        sql += staleClause(includeStale)
        
        let prior: [String: Double]
        if let sessionId, !sessionId.isEmpty {
            let windowMin = Genome.int("priming.window_min")
            prior = (try? ComputeAxisPriorTransaction(
                sessionId: sessionId,
                windowSec: windowMin * 60,
                now: now
            )
                .perform(db)) ?? [:]
        } else {
            prior = [:]
        }
        
        let needsRerank = !prior.isEmpty
        let fetchLimit = Self.fetchPoolSize(limit: limit, needsRerank: needsRerank)
        sql += Self.noteAggregationSQL
        
        do {
            arguments.append(fetchLimit)
            
            let rawRows: [SearchRow]
            do {
                rawRows = try fetchRows(db, sql: sql, arguments: arguments)
            } catch {
                if raw { throw SearchError.invalidRawQuery(matchExpr) }
                
                throw error
            }
            
            if !needsRerank {
                return Array(rawRows.prefix(limit))
            }
            
            return Self.rerank(rawRows, prior: prior, limit: limit) { row in row.axis }
        }
    }
    
    static func rerank<T>(
        _ pool: [T],
        prior: [String: Double],
        limit: Int,
        axisOf: (T) -> String
    ) -> [T] {
        let alpha = Genome.double("priming.alpha")
        let poolCount = Double(pool.count)
        let scored: [(index: Int, score: Double, item: T)] = pool.enumerated()
            .map { index, item in
                let rankScore = poolCount - Double(index)
                let axisBoost = alpha * (prior[axisOf(item)] ?? 0) * poolCount
                
                return (index, rankScore + axisBoost, item)
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
    private static func staleClause(_ includeStale: Bool) -> String {
        includeStale ? "" : " AND \(Policy.fresh())"
    }
    
    private static func fetchRows(
        _ db: Database,
        sql: String,
        arguments: [DatabaseValueConvertible?]
    ) throws -> [SearchRow] {
        let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(arguments))
        
        return rows.map { row in rowToSearchRow(row, hasExtra: false) }
    }
    
    private static func rowToSearchRow(_ row: Row, hasExtra: Bool) -> SearchRow {
        let section = (row["section"] as String?).flatMap { value in value.isEmpty ? nil : value }
        
        return (
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
