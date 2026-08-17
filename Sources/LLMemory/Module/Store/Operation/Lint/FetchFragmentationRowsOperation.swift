//
//  FetchFragmentationRowsOperation.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct FetchFragmentationRowsOperation: GRDBReadOperation {
    // MARK: - Initializer
    init() { }

    // MARK: - Public
    func execute(_ db: Database) throws -> [FragmentationRow] {
        try Row.fetchAll(db, sql: """
            SELECT n.id,
                   (SELECT COUNT(*) FROM note_links l
                      JOIN notes o ON o.id = CASE WHEN l.src = n.id THEN l.dst ELSE l.src END
                     WHERE (l.src = n.id OR l.dst = n.id)) AS link_n,
                   (SELECT COUNT(*) FROM entity_index WHERE note_id = n.id) AS ent_n,
                   (SELECT COUNT(*) FROM tags WHERE note_id = n.id) AS tag_n
            FROM notes n
            WHERE \(Policy.notEager())
            """).map { row in
            FragmentationRow(
                nid: row["id"],
                linkN: row["link_n"] as Int? ?? 0,
                entN: row["ent_n"] as Int? ?? 0,
                tagN: row["tag_n"] as Int? ?? 0
            )
        }
    }

    // MARK: - Private
}
