//
//  Search.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

public struct Search: Sendable {
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
        SELECT n.id, n.title, n.summary,
               (SELECT group_concat(tag, ',') FROM tags WHERE note_id = n.id) AS tags,
               (COALESCE(n.stale, 0) OR COALESCE((SELECT source_stale FROM note_source WHERE note_id = n.id), 0)) AS is_stale,
               f.section AS section, MIN(rank) AS best_rank
        """
    
    private let framing = Framing()

    private let policy = Policy()

    // MARK: - Initializer
    // MARK: - Public
    // The one place that decides what "this note carries this tag" means in SQL.
    // Aliases exist so a caller may spell a tag either way, and only the canonical
    // spelling is stored on the note — so the resolution belongs here, with the
    // clause it guards, rather than at each call site.
    func tagClause(
        _ db: Database,
        tags: [String],
        negated: Bool = false
    ) throws -> (clause: String, arguments: [String]) {
        guard !tags.isEmpty else { return ("", []) }

        let canonical = try tags.map { tag in
            try CanonicalizeTagTransaction(tag: tag).perform(db)
        }

        if negated {
            let placeholders = canonical.map { _ in "?" }.joined(separator: ",")

            return (
                "NOT EXISTS (SELECT 1 FROM tags t WHERE t.note_id = n.id"
                    + " AND t.tag IN (\(placeholders)))",
                canonical
            )
        }

        let clauses = canonical.map { _ in
            "EXISTS (SELECT 1 FROM tags t WHERE t.note_id = n.id AND t.tag = ?)"
        }

        return (clauses.joined(separator: " AND "), canonical)
    }

    func fetchPoolSize(limit: Int, needsRerank: Bool) -> Int {
        needsRerank ? limit + min(limit * 2, 30) : limit
    }
    
    func ftsMatchExpr(_ query: String, raw: Bool) -> String? {
        if raw {
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            
            return trimmed.isEmpty ? nil : trimmed
        }
        
        let parts = framing.extractKeywords(query)
            .map { keyword in "\"\(keyword.replacingOccurrences(of: "\"", with: ""))\"" }
        
        return parts.isEmpty ? nil : parts.joined(separator: " OR ")
    }
    

    
    // The boost takes the item's *strongest* reinstated tag rather than the sum:
    // a note that carries five tags is not five times more primed, and summing
    // would make tag count itself a ranking signal.
    func rerank<T>(
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
    func staleClause(_ includeStale: Bool) -> String {
        includeStale ? "" : " AND \(policy.fresh())"
    }
    
    func fetchRows(
        _ db: Database,
        sql: String,
        arguments: [DatabaseValueConvertible?]
    ) throws -> [SearchRow] {
        let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(arguments))
        
        return rows.map { row in rowToSearchRow(row, hasExtra: false) }
    }
    
    private func rowToSearchRow(_ row: Row, hasExtra: Bool) -> SearchRow {
        let section = (row["section"] as String?).flatMap { value in value.isEmpty ? nil : value }
        
        return SearchRow(
            path: Paths.relativeFile(forId: row["id"] as String),
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
