//
//  CitationRewriter.swift
//  LLMemory
//
//  Created by JSilver on 8/17/26.
//

import Foundation
import GRDB

// Re-addressing is renaming, and a rename that leaves the corpus pointing at
// the old name is a rename that manufactures dangling references. There is no
// alias table to soften this: the citations themselves move, so the resolver
// stays a single exact match and no old name outlives the note.
//
// It edits note files, so it is not an operation. What the database knows —
// who cites whom — it asks for; the rest is the corpus.
struct CitationRewriter {
    // MARK: - Initializer
    // MARK: - Public
    // The notes whose text was changed. Not best-effort: with no alias table,
    // a citation this loop fails to rewrite is a reference that breaks, so an
    // unreadable citer fails the whole re-addressing instead.
    @discardableResult
    func rewrite(
        _ db: Database,
        _ brain: BrainContext,
        from: String,
        to: String
    ) throws -> [String] {
        guard from != to else { return [] }

        let citers = try FetchInboundCitersOperation(marker: from, excluding: to).execute(db)
        var rewritten: [String] = []

        for citer in citers {
            let file = brain.layout.file(forId: citer)
            let text = try String(contentsOf: file, encoding: .utf8)

            // Both citation forms, because the resolver treats them as one.
            let updated = text
                .replacingOccurrences(of: "`\(from)`", with: "`\(to)`")
                .replacingOccurrences(of: "[[\(from)]]", with: "[[\(to)]]")

            guard updated != text else { continue }

            try updated.write(to: file, atomically: true, encoding: .utf8)
            try ReindexNoteFileOperation(
                noteId: try brain.requireNoteId(of: file),
                path: file
            ).execute(db)
            rewritten.append(citer)
        }

        return rewritten
    }

    // MARK: - Private
}
