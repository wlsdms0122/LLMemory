//
//  ExpandLinksTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct ExpandLinksTransaction: GRDBBrainReadTransaction {
    // MARK: - Property
    let noteIds: [String]
    let hops: Int
    let minWeight: Double?
    let limit: Int
    let kind: LinkKind?

    // MARK: - Initializer
    init(
        noteIds: [String],
        hops: Int = 1,
        minWeight: Double? = nil,
        limit: Int = 10,
        kind: LinkKind? = nil
    ) {
        self.noteIds = noteIds
        self.hops = hops
        self.minWeight = minWeight
        self.limit = limit
        self.kind = kind
    }

    // MARK: - Public
    func perform(_ db: Database, _ brain: BrainContext) throws -> [ExpandedNote] {
        guard !noteIds.isEmpty else { return [] }

        let floor = minWeight ?? brain.genes.double("links.neighbor_floor")
        var seen: [String: (note: ExpandedNote, rankWeight: Double)] = [:]
        var frontier = Set(noteIds)
        var visited = Set(noteIds)

        for _ in 0..<hops {
            if frontier.isEmpty { break }

            let frontierIds = Array(frontier)
            let placeholders = Array(repeating: "?", count: frontierIds.count)
                .joined(separator: ",")
            var sql = """
                SELECT n.id, n.title, n.summary, l.weight,
                       \(LinkRanking.weightSQL("l", brain)) AS rank_w
                FROM note_links l
                JOIN notes n ON n.id = CASE WHEN l.src IN (\(placeholders)) THEN l.dst ELSE l.src END
                WHERE (l.src IN (\(placeholders)) OR l.dst IN (\(placeholders)))
                  AND l.weight >= ?
                  AND \(Policy.surface())
                """
            var arguments: [DatabaseValueConvertible?] = []
            arguments.append(contentsOf: frontierIds as [DatabaseValueConvertible?])
            arguments.append(contentsOf: frontierIds as [DatabaseValueConvertible?])
            arguments.append(contentsOf: frontierIds as [DatabaseValueConvertible?])
            arguments.append(floor)

            if let kind {
                sql += " AND l.kind = ?"
                arguments.append(kind.rawValue)
            }

            let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(arguments))
            var newFrontier = Set<String>()

            for row in rows {
                let noteId: String = row["id"]

                if visited.contains(noteId) { continue }

                let rankWeight: Double = row["rank_w"]

                if let previous = seen[noteId], previous.rankWeight >= rankWeight {
                } else {
                    seen[noteId] = (
                        ExpandedNote(
                            id: noteId,
                            title: row["title"],
                            summary: row["summary"] as String?,
                            path: brain.paths.relativeFile(forId: row["id"] as String),
                            weight: row["weight"],
                            rankWeight: rankWeight
                        ),
                        rankWeight
                    )
                }

                newFrontier.insert(noteId)
            }

            visited.formUnion(newFrontier)
            frontier = newFrontier
        }

        return seen.values
            .sorted { lhs, rhs in
                lhs.rankWeight != rhs.rankWeight
                    ? lhs.rankWeight > rhs.rankWeight
                    : lhs.note.id < rhs.note.id
            }
            .prefix(limit)
            .map { entry in entry.note }
    }

    // MARK: - Private
}
