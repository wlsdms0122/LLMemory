//
//  SourceTracking.swift
//  LLMemory
//
//  Created by JSilver on 8/17/26.
//

import Foundation
import GRDB

// What note_source holds for one note: the fingerprint of the files it was
// written from, and whether they have drifted since. What the note declares
// lives in its frontmatter, not here — this row is only what was observed.
struct SourceTracking: Sendable {
    // MARK: - Property
    let noteId: String
    let sourceHash: String?
    let declHash: String?
    let stale: Bool

    // MARK: - Initializer
    init(_ row: Row) {
        noteId = row["note_id"]
        sourceHash = row["source_hash"] as String?
        declHash = row["decl_hash"] as String?
        stale = (row["source_stale"] as Int? ?? 0) == 1
    }

    // MARK: - Public
    // MARK: - Private
}
