//
//  FetchSurfaceLinkPairsTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct FetchSurfaceLinkPairsTransaction: GRDBReadTransaction {
    // MARK: - Initializer
    init() { }

    // MARK: - Public
    func perform(_ db: Database) throws -> [(src: String, dst: String)] {
        try Row.fetchAll(db, sql: """
            SELECT l.src, l.dst FROM note_links l
            JOIN notes ns ON ns.id = l.src AND \(Policy.surface("ns"))
            JOIN notes nd ON nd.id = l.dst AND \(Policy.surface("nd"))
            """).map { row in (src: row["src"] as String, dst: row["dst"] as String) }
    }

    // MARK: - Private
}
