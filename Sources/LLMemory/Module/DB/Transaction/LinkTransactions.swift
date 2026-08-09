//
//  LinkTransactions.swift
//  LLMemory
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import GRDB

// The link-graph vocabulary — edge kinds, their direction/lifecycle
// classes, and the note_links transactions.
public enum Links {
    public struct Distribution {
        // MARK: - Property
        public let byKind: [(kind: String, count: Int, min: Double, avg: Double, max: Double)]
        public let weightBuckets: [String: Int]
        public let topDegree: [(id: String, axis: String, title: String, degree: Int)]

        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }

    public struct ExpandedNote {
        // MARK: - Property
        public let id: String
        public let axis: String
        public let title: String
        public let summary: String?
        public let path: String
        public let weight: Double
        public let rankWeight: Double

        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }

    struct Edge {
        // MARK: - Property
        let other: String
        let kind: String
        let weight: Double
        let createdAt: Int
        let lastActivatedAt: Int
        let provenance: String?

        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }

    struct Neighbor {
        // MARK: - Property
        let id: String
        let axis: String
        let title: String
        let summary: String?
        let path: String
        let kind: String
        let weight: Double

        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }

    // MARK: - Property
    static let kindCooccur = "cooccur"
    static let kindReference = "reference"
    static let kindMergeAncestor = "merge_ancestor"
    static let kindSupersedes = "supersedes"
    static let kindPromotedTo = "promoted_to"
    static let kindSibling = "sibling"
    static let kindAssoc = "assoc"

    static let undirectedKinds: Set<String> = [kindCooccur, kindAssoc, kindSibling]
    static let directedKinds: Set<String> = [
        kindReference, kindMergeAncestor, kindSupersedes, kindPromotedTo
    ]
    static let learnedKinds: Set<String> = [kindCooccur, kindAssoc]
    static let lineageKinds: Set<String> = [kindPromotedTo, kindSupersedes, kindMergeAncestor]
    static let deleteBlockingKinds: Set<String> = [
        kindReference, kindPromotedTo, kindSupersedes, kindMergeAncestor, kindSibling
    ]
    static let deleteNonBlockingKinds: Set<String> = learnedKinds
    static let allKinds: Set<String> = [
        kindCooccur, kindReference, kindMergeAncestor, kindSupersedes, kindPromotedTo, kindAssoc,
        kindSibling
    ]

    static var siblingRankWeight: Double {
        Genome.double("links.sibling_rank_weight")
    }

    // MARK: - Initializer
    // MARK: - Public
    static func rankWeightSQL(_ alias: String) -> String {
        "(\(alias).weight * (CASE WHEN \(alias).kind = '\(kindSibling)' THEN \(siblingRankWeight) ELSE 1.0 END))"
    }

    static func normalize(src: String, dst: String, kind: String) -> (String, String)? {
        if src == dst { return nil }
        if undirectedKinds.contains(kind) && src > dst { return (dst, src) }

        return (src, dst)
    }

    // MARK: - Private
}

struct InsertLineageLinkTransaction: GRDBTransaction {
    // MARK: - Property
    let src: String
    let dst: String
    let kind: String
    let now: Int

    // MARK: - Initializer
    init(src: String, dst: String, kind: String, now: Int) {
        self.src = src
        self.dst = dst
        self.kind = kind
        self.now = now
    }

    // MARK: - Public
    func perform(_ db: Database) throws {
        guard let (source, destination) = Links.normalize(src: src, dst: dst, kind: kind) else { return }

        try db.execute(sql: """
            INSERT OR IGNORE INTO note_links
              (src, dst, kind, weight, created_at, last_activated_at)
            VALUES (?, ?, ?, ?, ?, ?)
            """, arguments: [source, destination, kind, 1.0, now, now])
    }

    // MARK: - Private
}

struct LinkSiblingsTransaction: GRDBTransaction {
    // MARK: - Property
    let ids: [String]
    let now: Int

    // MARK: - Initializer
    init(ids: [String], now: Int) {
        self.ids = ids
        self.now = now
    }

    // MARK: - Public
    func perform(_ db: Database) throws {
        let sorted = ids.sorted()

        guard sorted.count >= 2 else { return }

        for (index, left) in sorted.enumerated() {
            for right in sorted.dropFirst(index + 1) {
                guard let (src, dst) = Links.normalize(
                    src: left,
                    dst: right,
                    kind: Links.kindSibling
                ) else {
                    continue
                }

                try db.execute(sql: """
                    INSERT OR IGNORE INTO note_links
                      (src, dst, kind, weight, created_at, last_activated_at)
                    VALUES (?, ?, ?, ?, ?, ?)
                    """, arguments: [src, dst, Links.kindSibling, 1.0, now, now])
            }
        }
    }

    // MARK: - Private
}

struct DeleteNoteLinksTransaction: GRDBTransaction {
    // MARK: - Property
    let noteId: String

    // MARK: - Initializer
    init(noteId: String) {
        self.noteId = noteId
    }

    // MARK: - Public
    func perform(_ db: Database) throws {
        try db.execute(
            sql: "DELETE FROM note_links WHERE src = ? OR dst = ?",
            arguments: [noteId, noteId]
        )
    }

    // MARK: - Private
}

struct FetchLinkDistributionTransaction: GRDBTransaction {
    // MARK: - Initializer
    init() { }

    // MARK: - Public
    func perform(_ db: Database) throws -> Links.Distribution {
        let byKindRows = try Row.fetchAll(db, sql: """
            SELECT kind, COUNT(*) AS c, MIN(weight) AS mn, AVG(weight) AS av, MAX(weight) AS mx
            FROM note_links GROUP BY kind ORDER BY kind
            """)
        let byKind = byKindRows.map { row in
            (
                kind: row["kind"] as String,
                count: row["c"] as Int,
                min: row["mn"] as Double? ?? 0,
                avg: round((row["av"] as Double? ?? 0) * 1000) / 1000,
                max: row["mx"] as Double? ?? 0
            )
        }
        let bucketRow = try Row.fetchOne(db, sql: """
            SELECT
              SUM(CASE WHEN weight < 0.3 THEN 1 ELSE 0 END) AS w_lt_03,
              SUM(CASE WHEN weight >= 0.3 AND weight < 0.6 THEN 1 ELSE 0 END) AS w_03_06,
              SUM(CASE WHEN weight >= 0.6 AND weight < 0.9 THEN 1 ELSE 0 END) AS w_06_09,
              SUM(CASE WHEN weight >= 0.9 THEN 1 ELSE 0 END) AS w_ge_09
            FROM note_links
            """)
        let buckets: [String: Int] = [
            "[0.0-0.3)": bucketRow?["w_lt_03"] as Int? ?? 0,
            "[0.3-0.6)": bucketRow?["w_03_06"] as Int? ?? 0,
            "[0.6-0.9)": bucketRow?["w_06_09"] as Int? ?? 0,
            "[0.9- ]": bucketRow?["w_ge_09"] as Int? ?? 0
        ]
        let topRows = try Row.fetchAll(db, sql: """
            SELECT n.id, n.axis, n.title, COUNT(*) AS deg
            FROM note_links l
            JOIN notes n ON n.id IN (l.src, l.dst)
            GROUP BY n.id ORDER BY deg DESC, n.id LIMIT 5
            """)
        let topDegree = topRows.map { row in
            (
                id: row["id"] as String,
                axis: row["axis"] as String,
                title: row["title"] as String,
                degree: row["deg"] as Int
            )
        }

        return Links.Distribution(
            byKind: byKind,
            weightBuckets: buckets,
            topDegree: topDegree
        )
    }

    // MARK: - Private
}

struct RedirectLinksForMergeTransaction: GRDBTransaction {
    // MARK: - Property
    let fromId: String
    let intoId: String

    // MARK: - Initializer
    init(fromId: String, intoId: String) {
        self.fromId = fromId
        self.intoId = intoId
    }

    // MARK: - Public
    func perform(_ db: Database) throws {
        let cap = 1.0
        let rows = try Row.fetchAll(db, sql: """
            SELECT src, dst, kind, weight, created_at, last_activated_at, provenance
            FROM note_links WHERE src = ? OR dst = ?
            """, arguments: [fromId, fromId])

        for row in rows {
            let kind: String = row["kind"]

            if NoteArtifacts.reconstructableLinkKinds.contains(kind) { continue }

            let newSrc = (row["src"] as String) == fromId ? intoId : (row["src"] as String)
            let newDst = (row["dst"] as String) == fromId ? intoId : (row["dst"] as String)

            guard let (source, destination) = Links.normalize(
                src: newSrc,
                dst: newDst,
                kind: kind
            ) else {
                continue
            }

            let weight: Double = row["weight"]
            let createdAt: Int = row["created_at"]
            let lastActivatedAt: Int = row["last_activated_at"]
            let provenance: String? = row["provenance"]

            if Links.undirectedKinds.contains(kind) {
                try db.execute(sql: """
                    INSERT INTO note_links (src, dst, kind, weight, created_at, last_activated_at, provenance)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(src, dst, kind) DO UPDATE SET
                      weight = MIN(?, weight + excluded.weight),
                      last_activated_at = MAX(last_activated_at, excluded.last_activated_at)
                    """, arguments: [
                        source, destination, kind, min(weight, cap),
                        createdAt, lastActivatedAt, provenance, cap
                    ])
            } else {
                try db.execute(sql: """
                    INSERT OR IGNORE INTO note_links (src, dst, kind, weight, created_at, last_activated_at, provenance)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    """, arguments: [
                        source, destination, kind, weight,
                        createdAt, lastActivatedAt, provenance
                    ])
            }
        }

        try db.execute(
            sql: "DELETE FROM note_links WHERE src = ? OR dst = ?",
            arguments: [fromId, fromId]
        )
    }

    // MARK: - Private
}

struct NormalizeUndirectedLinksTransaction: GRDBTransaction {
    // MARK: - Property
    let nodeId: String

    // MARK: - Initializer
    init(nodeId: String) {
        self.nodeId = nodeId
    }

    // MARK: - Public
    func perform(_ db: Database) throws {
        let kinds = Array(Links.undirectedKinds)
        let placeholders = kinds.map { _ in "?" }.joined(separator: ", ")
        let swapArguments = StatementArguments(kinds + [nodeId, nodeId])

        try db.execute(
            sql: "UPDATE OR IGNORE note_links SET src = dst, dst = src WHERE kind IN (\(placeholders)) AND src > dst AND (src = ? OR dst = ?)",
            arguments: swapArguments
        )
        try db.execute(
            sql: "DELETE FROM note_links WHERE kind IN (\(placeholders)) AND src > dst AND (src = ? OR dst = ?)",
            arguments: swapArguments
        )
    }

    // MARK: - Private
}

struct FetchInboundBlockersTransaction: GRDBTransaction {
    // MARK: - Property
    let noteId: String
    let limit: Int

    // MARK: - Initializer
    init(noteId: String, limit: Int = 5) {
        self.noteId = noteId
        self.limit = limit
    }

    // MARK: - Public
    func perform(_ db: Database) throws -> [String] {
        let directed = Array(Links.deleteBlockingKinds.intersection(Links.directedKinds))
        let symmetric = Array(Links.deleteBlockingKinds.intersection(Links.undirectedKinds))
        let directedPlaceholders = directed.map { _ in "?" }.joined(separator: ",")
        let symmetricPlaceholders = symmetric.map { _ in "?" }.joined(separator: ",")
        var arguments: [DatabaseValueConvertible?] = [noteId]
        arguments.append(contentsOf: directed as [DatabaseValueConvertible?])
        arguments.append(contentsOf: [noteId, noteId, noteId] as [DatabaseValueConvertible?])
        arguments.append(contentsOf: symmetric as [DatabaseValueConvertible?])
        arguments.append(limit)

        return try String.fetchAll(db, sql: """
            SELECT other FROM (
              SELECT src AS other FROM note_links WHERE dst = ? AND kind IN (\(directedPlaceholders))
              UNION
              SELECT CASE WHEN src = ? THEN dst ELSE src END AS other FROM note_links
              WHERE (src = ? OR dst = ?) AND kind IN (\(symmetricPlaceholders))
            ) ORDER BY other LIMIT ?
            """, arguments: StatementArguments(arguments))
    }

    // MARK: - Private
}

struct FetchLinkFanTransaction: GRDBTransaction {
    // MARK: - Property
    let fromId: String

    // MARK: - Initializer
    init(fromId: String) {
        self.fromId = fromId
    }

    // MARK: - Public
    func perform(_ db: Database) throws -> (outEdges: [Links.Edge], inEdges: [Links.Edge]) {
        let outboundRows = try Row.fetchAll(db, sql: """
            SELECT dst, kind, weight, created_at, last_activated_at, provenance
            FROM note_links WHERE src = ?
            """, arguments: [fromId])
        let inboundRows = try Row.fetchAll(db, sql: """
            SELECT src, kind, weight, created_at, last_activated_at, provenance
            FROM note_links WHERE dst = ?
            """, arguments: [fromId])
        let outEdges: [Links.Edge] = outboundRows.map { row in
            Links.Edge(
                other: row["dst"],
                kind: row["kind"],
                weight: row["weight"],
                createdAt: row["created_at"],
                lastActivatedAt: row["last_activated_at"],
                provenance: row["provenance"]
            )
        }
        let inEdges: [Links.Edge] = inboundRows.map { row in
            Links.Edge(
                other: row["src"],
                kind: row["kind"],
                weight: row["weight"],
                createdAt: row["created_at"],
                lastActivatedAt: row["last_activated_at"],
                provenance: row["provenance"]
            )
        }

        return (outEdges, inEdges)
    }

    // MARK: - Private
}

struct AddLinkTransaction: GRDBTransaction {
    // MARK: - Property
    let src: String
    let dst: String
    let kind: String
    let weight: Double
    let createdAt: Int
    let lastActivatedAt: Int
    let provenance: String?

    // MARK: - Initializer
    init(
        src: String,
        dst: String,
        kind: String,
        weight: Double,
        createdAt: Int,
        lastActivatedAt: Int,
        provenance: String? = nil
    ) {
        self.src = src
        self.dst = dst
        self.kind = kind
        self.weight = weight
        self.createdAt = createdAt
        self.lastActivatedAt = lastActivatedAt
        self.provenance = provenance
    }

    // MARK: - Public
    func perform(_ db: Database) throws {
        if src == dst { return }

        try db.execute(sql: """
            INSERT OR IGNORE INTO note_links
              (src, dst, kind, weight, created_at, last_activated_at, provenance)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """, arguments: [src, dst, kind, weight, createdAt, lastActivatedAt, provenance])
    }

    // MARK: - Private
}

struct StrengthenLinksTransaction: GRDBTransaction {
    // MARK: - Property
    let pairs: [(String, String)]
    let kind: String
    let step: Double?
    let cap: Double?

    // MARK: - Initializer
    init(
        pairs: [(String, String)],
        kind: String = Links.kindCooccur,
        step: Double? = nil,
        cap: Double? = nil
    ) {
        self.pairs = pairs
        self.kind = kind
        self.step = step
        self.cap = cap
    }

    // MARK: - Public
    @discardableResult
    func perform(_ db: Database) throws -> Int {
        guard !pairs.isEmpty else { return 0 }

        let stepValue = step ?? Genome.double("links.strengthen_step")
        let now = Int(Date().timeIntervalSince1970)
        var strengthened = 0

        for (src, dst) in pairs {
            guard let (source, destination) = Links.normalize(
                src: src,
                dst: dst,
                kind: kind
            ) else {
                continue
            }

            if let cap {
                try db.execute(sql: """
                    INSERT INTO note_links (src, dst, kind, weight, created_at, last_activated_at)
                    VALUES (?, ?, ?, ?, ?, ?)
                    ON CONFLICT(src, dst, kind) DO UPDATE SET
                      weight = MIN(?, weight + excluded.weight),
                      last_activated_at = excluded.last_activated_at
                    """, arguments: [
                        source, destination, kind, min(stepValue, cap), now, now, cap
                    ])
            } else {
                try db.execute(sql: """
                    INSERT INTO note_links (src, dst, kind, weight, created_at, last_activated_at)
                    VALUES (?, ?, ?, ?, ?, ?)
                    ON CONFLICT(src, dst, kind) DO UPDATE SET
                      weight = weight + excluded.weight,
                      last_activated_at = excluded.last_activated_at
                    """, arguments: [source, destination, kind, stepValue, now, now])
            }

            strengthened += 1
        }

        return strengthened
    }

    // MARK: - Private
}

struct FetchLinkNeighborsTransaction: GRDBTransaction {
    // MARK: - Property
    let noteId: String
    let minWeight: Double?
    let limit: Int
    let kind: String?

    // MARK: - Initializer
    init(noteId: String, minWeight: Double? = nil, limit: Int = 5, kind: String? = nil) {
        self.noteId = noteId
        self.minWeight = minWeight
        self.limit = limit
        self.kind = kind
    }

    // MARK: - Public
    func perform(_ db: Database) throws -> [Links.Neighbor] {
        let floor = minWeight ?? Genome.double("links.neighbor_floor")
        var sql = """
            SELECT n.id, n.axis, n.title, n.summary, n.path, l.kind, l.weight,
                   \(Links.rankWeightSQL("l")) AS rank_w
            FROM note_links l
            JOIN notes n ON n.id = CASE WHEN l.src = ? THEN l.dst ELSE l.src END
            WHERE (l.src = ? OR l.dst = ?) AND l.weight >= ?
              AND \(Policy.surface())
            """
        var arguments: [DatabaseValueConvertible?] = [noteId, noteId, noteId, floor]

        if let kind {
            sql += " AND l.kind = ?"
            arguments.append(kind)
        }

        sql += " ORDER BY rank_w DESC, n.id LIMIT ?"
        arguments.append(limit)

        let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(arguments))

        return rows.map { row in
            Links.Neighbor(
                id: row["id"],
                axis: row["axis"],
                title: row["title"],
                summary: row["summary"] as String?,
                path: row["path"],
                kind: row["kind"],
                weight: row["weight"]
            )
        }
    }

    // MARK: - Private
}

struct ExpandLinksTransaction: GRDBTransaction {
    // MARK: - Property
    let noteIds: [String]
    let hops: Int
    let minWeight: Double?
    let limit: Int
    let kind: String?

    // MARK: - Initializer
    init(
        noteIds: [String],
        hops: Int = 1,
        minWeight: Double? = nil,
        limit: Int = 10,
        kind: String? = nil
    ) {
        self.noteIds = noteIds
        self.hops = hops
        self.minWeight = minWeight
        self.limit = limit
        self.kind = kind
    }

    // MARK: - Public
    func perform(_ db: Database) throws -> [Links.ExpandedNote] {
        guard !noteIds.isEmpty else { return [] }

        let floor = minWeight ?? Genome.double("links.neighbor_floor")
        var seen: [String: (note: Links.ExpandedNote, rankWeight: Double)] = [:]
        var frontier = Set(noteIds)
        var visited = Set(noteIds)

        for _ in 0..<hops {
            if frontier.isEmpty { break }

            let frontierIds = Array(frontier)
            let placeholders = Array(repeating: "?", count: frontierIds.count)
                .joined(separator: ",")
            var sql = """
                SELECT n.id, n.axis, n.title, n.summary, n.path, l.weight,
                       \(Links.rankWeightSQL("l")) AS rank_w
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
                arguments.append(kind)
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
                        Links.ExpandedNote(
                            id: noteId,
                            axis: row["axis"],
                            title: row["title"],
                            summary: row["summary"] as String?,
                            path: row["path"],
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

struct RebirthLinksTransaction: GRDBTransaction {
    // MARK: - Property
    let rankedIds: [(String, Double)]
    let cap: Double

    // MARK: - Initializer
    init(rankedIds: [(String, Double)], cap: Double = 1.0) {
        self.rankedIds = rankedIds
        self.cap = cap
    }

    init(noteIds: [String], factor: Double? = nil, cap: Double = 1.0) {
        let factor = factor ?? Genome.double("rebirth.default_factor")

        self.init(rankedIds: noteIds.map { id in (id, factor) }, cap: cap)
    }

    // MARK: - Public
    @discardableResult
    func perform(_ db: Database) throws -> Int {
        guard rankedIds.count >= 2 else { return 0 }

        var factorOf: [String: Double] = [:]

        for (id, factor) in rankedIds {
            factorOf[id] = max(factorOf[id] ?? 0, factor)
        }

        let ids = Array(factorOf.keys)
        let now = Int(Date().timeIntervalSince1970)
        let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ",")
        var arguments: [DatabaseValueConvertible?] = []
        arguments.append(contentsOf: ids as [DatabaseValueConvertible?])
        arguments.append(contentsOf: ids as [DatabaseValueConvertible?])

        let kindPlaceholders = Array(repeating: "?", count: Links.learnedKinds.count)
            .joined(separator: ",")
        arguments.append(contentsOf: Array(Links.learnedKinds) as [DatabaseValueConvertible?])

        let rows = try Row.fetchAll(db, sql: """
            SELECT src, dst, kind, weight FROM note_links
            WHERE src IN (\(placeholders)) AND dst IN (\(placeholders)) AND kind IN (\(kindPlaceholders))
            """, arguments: StatementArguments(arguments))
        var updated = 0

        for row in rows {
            let source: String = row["src"]
            let destination: String = row["dst"]
            let kind: String = row["kind"]
            let weight: Double = row["weight"]
            let factor = max(factorOf[source] ?? 1.0, factorOf[destination] ?? 1.0)
            let newWeight = min(cap, weight * factor)

            if newWeight > weight {
                try db.execute(sql: """
                    UPDATE note_links SET weight = ?, last_activated_at = ?
                    WHERE src = ? AND dst = ? AND kind = ?
                    """, arguments: [newWeight, now, source, destination, kind])
                updated += 1
            }
        }

        return updated
    }

    // MARK: - Private
}

struct DecayAndPruneLinksTransaction: GRDBTransaction {
    // MARK: - Property
    let factor: Double?
    let floor: Double?

    // MARK: - Initializer
    init(factor: Double? = nil, floor: Double? = nil) {
        self.factor = factor
        self.floor = floor
    }

    // MARK: - Public
    func perform(_ db: Database) throws -> (decayed: Int, pruned: Int) {
        let factor = self.factor ?? Genome.double("links.decay_factor")
        let floor = self.floor ?? Genome.double("links.prune_floor")
        let kindPlaceholders = Array(repeating: "?", count: Links.learnedKinds.count)
            .joined(separator: ",")
        let kinds = Array(Links.learnedKinds) as [DatabaseValueConvertible?]

        try db.execute(
            sql: "UPDATE note_links SET weight = weight * ? WHERE kind IN (\(kindPlaceholders))",
            arguments: StatementArguments([factor as DatabaseValueConvertible?] + kinds)
        )

        let decayed = db.changesCount

        try db.execute(
            sql: "DELETE FROM note_links WHERE weight < ? AND kind IN (\(kindPlaceholders))",
            arguments: StatementArguments([floor as DatabaseValueConvertible?] + kinds)
        )

        let pruned = db.changesCount

        return (decayed, pruned)
    }

    // MARK: - Private
}
