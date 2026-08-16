//
//  SearchRow.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

// One FTS hit — a struct rather than a tuple so surfaces can encode it
// without mirroring.
//
// The columns it is selected from live here too. A projection and the reader
// that maps back out of it are one decision, and while they were two files
// apart the reader kept carrying a field the projection had stopped selecting.
public struct SearchRow: Sendable {
    // MARK: - Property
    static let projectionSQL = """
        SELECT n.id, n.title, n.summary,
               (SELECT group_concat(tag, ',') FROM tags WHERE note_id = n.id) AS tags,
               (COALESCE(n.stale, 0) OR COALESCE((SELECT source_stale FROM note_source WHERE note_id = n.id), 0)) AS is_stale,
               f.section AS section, MIN(rank) AS best_rank
        """

    // One row per note, best-ranked first, with the id breaking ties so the
    // cut does not fall where SQLite happened to reach first.
    static let aggregationSQL = " GROUP BY n.id ORDER BY best_rank, n.id LIMIT ?"

    public let path: String
    public let id: String
    public let title: String
    public let summary: String?
    public let tagsCSV: String?
    public let isStale: Bool
    public let section: String?

    public var tags: [String] {
        (tagsCSV ?? "").split(separator: ",").map(String.init)
    }

    // MARK: - Initializer
    init(_ row: Row, _ layout: BrainLayout) {
        path = layout.relativeFile(forId: row["id"] as String)
        id = row["id"]
        title = row["title"]
        summary = row["summary"] as String?
        tagsCSV = row["tags"] as String?
        isStale = (row["is_stale"] as Int? ?? 0) != 0
        section = (row["section"] as String?).flatMap { value in value.isEmpty ? nil : value }
    }

    // MARK: - Public
    // MARK: - Private
}
