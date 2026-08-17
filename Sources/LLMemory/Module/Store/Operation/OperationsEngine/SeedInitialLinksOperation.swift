//
//  SeedInitialLinksOperation.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct SeedInitialLinksOperation: GRDBOperation {
    // MARK: - Property
    let nid: String
    let tags: [String]

    // MARK: - Initializer
    init(nid: String, tags: [String]) {
        self.nid = nid
        self.tags = tags
    }

    // MARK: - Public
    func execute(_ db: Database) throws {
        if tags.isEmpty { return }

        let placeholders = Array(repeating: "?", count: tags.count).joined(separator: ",")
        var arguments: [DatabaseValueConvertible] = []
        arguments.append(contentsOf: tags)
        arguments.append(nid)

        let rows = try Row.fetchAll(db, sql: """
            SELECT n.id, COUNT(*) AS shared,
                   (SELECT COUNT(*) FROM tags WHERE note_id = n.id) AS other_total
            FROM tags t JOIN notes n ON n.id = t.note_id
            WHERE t.tag IN (\(placeholders)) AND n.id != ?
            GROUP BY n.id
            ORDER BY shared DESC, n.id ASC
            LIMIT 5
            """, arguments: StatementArguments(arguments))

        if rows.isEmpty { return }

        let now = Int(Date().timeIntervalSince1970)
        let kind = LinkKind.cooccur
        let newTotal = tags.count

        for row in rows {
            let candidateId: String = row["id"]
            let shared: Int = row["shared"]
            let otherTotal: Int = row["other_total"] as Int? ?? 0

            guard let (source, destination) = kind.endpoints(src: nid, dst: candidateId) else {
                continue
            }

            let union = max(newTotal + otherTotal - shared, 1)
            let weight = max(Double(shared) / Double(union), 0.1)

            try db.execute(sql: """
                INSERT INTO note_links (src, dst, kind, weight, created_at, last_activated_at)
                VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT(src, dst, kind) DO UPDATE SET
                  weight = MIN(1.0, weight + excluded.weight),
                  last_activated_at = excluded.last_activated_at
                """, arguments: [source, destination, kind.rawValue, weight, now, now])
        }
    }

    // MARK: - Private
}
