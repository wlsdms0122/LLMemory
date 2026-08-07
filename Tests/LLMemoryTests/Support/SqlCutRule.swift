//
//  SqlCutRule.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/8/26.
//

import Foundation

// A LIMIT without a total order returns an arbitrary member of a tie. This decides whether one SQL
// literal cuts on a well-defined order.
struct SqlCutRule {
    // MARK: - Property
    // Columns unique enough to break a tie. Ordering on any of them makes the cut reproducible.
    private static let tiebreakColumns: Set<String> = [
        "id", "note_id", "rowid", "entity", "tag", "tag_a", "tag_b",
        "term", "key", "axis", "kind", "src", "dst", "path", "alias", "name",
        "other"
    ]
    
    // MARK: - Initializer
    // MARK: - Public
    func violation(body: String, file: String, line: Int) -> SqlCutViolation? {
        guard cuts(body) else { return nil }
        
        guard let clause = orderByClause(of: body) else {
            return SqlCutViolation(
                file: file,
                line: line,
                reason: "LIMIT cut without ORDER BY",
                snippet: Self.snippet(body)
            )
        }
        
        let columns = Self.columns(of: clause)
        
        if columns.contains(where: { column in Self.tiebreakColumns.contains(column) }) { return nil }
        
        return SqlCutViolation(
            file: file,
            line: line,
            reason: "ORDER BY has no unique tiebreak column (\(columns.joined(separator: ", ")))",
            snippet: Self.snippet(body)
        )
    }
    
    // MARK: - Private
    private func cuts(_ body: String) -> Bool {
        let upper = body.uppercased()
        
        guard upper.contains("LIMIT") else { return false }
        guard upper.contains("SELECT") || upper.contains("ORDER BY") else { return false }
        
        // LIMIT 1 on a unique lookup is a single row by construction, not a cut through a tie.
        let withoutSingleRow = body.replacingOccurrences(
            of: #"LIMIT\s+1\b"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        
        return withoutSingleRow.uppercased().contains("LIMIT")
    }
    
    private func orderByClause(of body: String) -> String? {
        guard let orderBy = body.range(of: "ORDER BY", options: [.caseInsensitive, .backwards]) else {
            return nil
        }
        
        var clause = String(body[orderBy.upperBound...])
        
        if let limit = clause.range(of: "LIMIT", options: .caseInsensitive) {
            clause = String(clause[..<limit.lowerBound])
        }
        
        return clause
    }
    
    private static func columns(of clause: String) -> [String] {
        clause
            .components(separatedBy: ",")
            .map { term in term.trimmingCharacters(in: .whitespacesAndNewlines) }
            .map { term in
                let head = term.components(separatedBy: .whitespaces).first ?? term
                
                return head.components(separatedBy: ".").last?.lowercased() ?? head.lowercased()
            }
    }
    
    private static func snippet(_ body: String) -> String {
        let flattened = body.components(separatedBy: .newlines)
            .map { line in line.trimmingCharacters(in: .whitespaces) }
            .joined(separator: " ")
        
        return String(flattened.prefix(140))
    }
}
