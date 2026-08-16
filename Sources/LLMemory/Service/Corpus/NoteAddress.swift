//
//  NoteAddress.swift
//  LLMemory
//
//  Created by JSilver on 8/16/26.
//

import Foundation

// The grammar of a note id: labels joined by dots. None of it needs a brain
// — what the parent of `a.b.c` is does not depend on where the files live,
// and saying so here keeps the questions that do need a home in one place
// rather than mixed in with the ones that never did.
enum NoteAddress {
    // MARK: - Property
    // An id is labels joined by dots, and the dots are directory separators.
    static let idRegex = try! NSRegularExpression(
        pattern: #"^[a-z0-9][a-z0-9-]*(\.[a-z0-9][a-z0-9-]*)*$"#
    )

    // MARK: - Initializer
    // MARK: - Public
    // One definition of what a prefix is, because three quietly different
    // ones is how two fields of the same response come to disagree.
    static func labels(of id: String) -> [String] {
        id.split(separator: ".").map(String.init)
    }

    // The ancestor of `id` that is `depth` labels long, or nil if the id is
    // shorter than that. `branch(of: "a.b.c", depth: 1)` is "a".
    static func branch(of id: String, depth: Int) -> String? {
        let labels = labels(of: id)

        guard labels.count >= depth, depth > 0 else { return nil }

        return labels.prefix(depth).joined(separator: ".")
    }

    // At or under: the address itself is part of its own branch. Everything
    // that aggregates over a branch means this — a note at `a.b` is as much a
    // member of a.b as `a.b.c` is.
    static func id(_ id: String, isWithin prefix: String) -> Bool {
        id == prefix || id.hasPrefix(prefix + ".")
    }

    // The SQL spelling of "the first `depth` labels of this id". Aggregation
    // belongs in SQLite — a hit log only grows — so the definition is shared
    // as an expression rather than by pulling rows out to group them in Swift.
    static func branchSQL(column: String, depth: Int = 1) -> String {
        precondition(depth == 1, "only the first label has a SQL spelling today")

        return """
            CASE WHEN instr(\(column), '.') > 0
                 THEN substr(\(column), 1, instr(\(column), '.') - 1)
                 ELSE \(column) END
            """
    }

    // MARK: - Private
}
