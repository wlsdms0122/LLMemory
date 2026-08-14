//
//  RewriteInboundCitationsTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

// Re-addressing is renaming, and a rename that leaves the corpus pointing at
// the old name is a rename that manufactures dangling references. There is no
// alias table to soften this: the citations themselves move, so the resolver
// stays a single exact match and no old name outlives the note.
//
// note_ref_markers is what makes it tractable — it records who cites whom
// whether or not the citation resolved, so the set of files to touch is known
// rather than searched for.
struct RewriteInboundCitationsTransaction: GRDBTransaction {
    // MARK: - Property
    let from: String
    let to: String

    // MARK: - Initializer
    init(from: String, to: String) {
        self.from = from
        self.to = to
    }

    // MARK: - Public
    @discardableResult
    func perform(_ db: Database) throws -> [String] {
        guard from != to else { return [] }

        let referrers = try String.fetchAll(
            db,
            sql: "SELECT DISTINCT src FROM note_ref_markers WHERE marker = ? AND src != ?",
            arguments: [from, to]
        )
        var rewritten: [String] = []

        for src in referrers.sorted() {
            let file = Paths.file(forId: src)
            // Not `try?`. With no alias table, a citation this loop fails to
            // rewrite is a reference that breaks — reporting success while
            // leaving one behind is the exact state the design forbids, so an
            // unreadable citer fails the whole re-addressing instead.
            let text = try String(contentsOf: file, encoding: .utf8)

            // Both citation forms, because the resolver treats them as one.
            let updated = text
                .replacingOccurrences(of: "`\(from)`", with: "`\(to)`")
                .replacingOccurrences(of: "[[\(from)]]", with: "[[\(to)]]")

            guard updated != text else { continue }

            try updated.write(to: file, atomically: true, encoding: .utf8)
            try ReindexNoteFileTransaction(path: file).perform(db)
            rewritten.append(src)
        }

        return rewritten
    }

    // MARK: - Private
}
