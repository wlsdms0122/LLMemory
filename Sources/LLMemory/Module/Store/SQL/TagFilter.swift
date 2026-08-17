//
//  TagFilter.swift
//  LLMemory
//
//  Created by JSilver on 8/16/26.
//

import Foundation
import GRDB

// What "this note carries this tag" means in SQL, decided once. Aliases exist
// so a caller may spell a tag either way while only the canonical spelling is
// stored on the note — so the resolution belongs with the clause it guards
// rather than at each call site, where one of them would forget.
enum TagFilter {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Public
    static func clause(
        _ db: Database,
        tags: [String],
        negated: Bool = false
    ) throws -> (clause: String, arguments: [String]) {
        guard !tags.isEmpty else { return ("", []) }

        let canonical = try tags.map { tag in
            try CanonicalizeTagOperation(tag: tag).execute(db)
        }

        if negated {
            let placeholders = canonical.map { _ in "?" }.joined(separator: ",")

            return (
                "NOT EXISTS (SELECT 1 FROM tags t WHERE t.note_id = n.id"
                    + " AND t.tag IN (\(placeholders)))",
                canonical
            )
        }

        // Each tag gets its own EXISTS: a note carries all of them or it is
        // not a match, which one IN over the set would not say.
        let clauses = canonical.map { _ in
            "EXISTS (SELECT 1 FROM tags t WHERE t.note_id = n.id AND t.tag = ?)"
        }

        return (clauses.joined(separator: " AND "), canonical)
    }

    // MARK: - Private
}
