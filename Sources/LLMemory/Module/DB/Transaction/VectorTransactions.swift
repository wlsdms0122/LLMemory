//
//  VectorTransactions.swift
//  LLMemory
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import GRDB

// note_vectors transactions — building the PPMI+SVD projection from the
// link graph and expanding by cosine neighborhood. The numerics live in
// VectorMath.
public struct VectorBuildResult: Sendable {
    // MARK: - Property
    public let noteCount: Int
    public let dim: Int
    public let builtAt: Int
    public let skipped: Bool
    public let reason: String

    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}

public struct VectorHit: Sendable {
    // MARK: - Property
    public let id: String
    public let axis: String
    public let title: String
    public let summary: String?
    public let path: String
    public let score: Double

    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}

struct FetchNoteVectorsTransaction: GRDBReadTransaction {
    // MARK: - Initializer
    init() { }

    // MARK: - Public
    func perform(_ db: Database) throws -> [String: [Float]] {
        var vectors: [String: [Float]] = [:]
        let rows = try Row.fetchAll(db, sql: "SELECT note_id, dim, vec FROM note_vectors")

        for row in rows {
            let noteId: String = row["note_id"]
            let dim: Int = row["dim"]

            guard let data: Data = row["vec"],
                data.count == dim * MemoryLayout<Float>.size
            else {
                continue
            }

            vectors[noteId] = data.withUnsafeBytes { buffer in
                Array(buffer.bindMemory(to: Float.self))
            }
        }

        return vectors
    }

    // MARK: - Private
}

struct BuildVectorsTransaction: GRDBTransaction {
    // MARK: - Initializer
    init() { }

    // MARK: - Public
    @discardableResult
    func perform(_ db: Database) throws -> VectorBuildResult {
        let now = Int(Date().timeIntervalSince1970)
        let noteIds = try String.fetchAll(
            db,
            sql: "SELECT id FROM notes WHERE \(Policy.surface("")) ORDER BY id"
        )
        let noteCount = noteIds.count

        if noteCount < 2 {
            return VectorBuildResult(
                noteCount: noteCount,
                dim: 0,
                builtAt: now,
                skipped: true,
                reason: "too few notes (\(noteCount))"
            )
        }

        let dim = min(Config.getInt("vectors.dim", default: 48), noteCount - 1)
        var indexById: [String: Int] = [:]

        for (index, id) in noteIds.enumerated() { indexById[id] = index }

        var matrix = [Double](repeating: 0, count: noteCount * noteCount)
        let links = try Row.fetchAll(db, sql: "SELECT src, dst, weight FROM note_links")

        for link in links {
            guard let source = indexById[link["src"] as String],
                let destination = indexById[link["dst"] as String]
            else {
                continue
            }

            let weight: Double = link["weight"]
            matrix[source * noteCount + destination] += weight
            matrix[destination * noteCount + source] += weight
        }

        var tagsOf: [Int: Set<String>] = [:]
        let tagRows = try Row.fetchAll(db, sql: "SELECT note_id, tag FROM tags")

        for row in tagRows {
            guard let index = indexById[row["note_id"] as String] else { continue }

            tagsOf[index, default: []].insert(row["tag"])
        }

        for left in 0..<noteCount {
            guard let leftTags = tagsOf[left], !leftTags.isEmpty else { continue }

            for right in (left + 1)..<noteCount {
                guard let rightTags = tagsOf[right], !rightTags.isEmpty else { continue }

                let intersection = leftTags.intersection(rightTags).count

                if intersection == 0 { continue }

                let jaccard = Double(intersection) / Double(leftTags.union(rightTags).count)
                let floor = jaccard * 0.3

                if matrix[left * noteCount + right] < floor {
                    matrix[left * noteCount + right] = floor
                    matrix[right * noteCount + left] = floor
                }
            }
        }

        let ppmi = VectorMath.computePPMI(matrix, n: noteCount)
        let projection = try VectorMath.truncatedSVD(ppmi, n: noteCount, k: dim)

        try db.execute(sql: "DELETE FROM note_vectors")

        for (index, id) in noteIds.enumerated() {
            var vector = [Float](repeating: 0, count: dim)

            for component in 0..<dim {
                vector[component] = Float(projection[index * dim + component])
            }

            let blob = vector.withUnsafeBufferPointer { buffer in Data(buffer: buffer) }

            try db.execute(sql: """
                INSERT INTO note_vectors (note_id, dim, vec, built_at)
                VALUES (?, ?, ?, ?)
                """, arguments: [id, dim, blob, now])
        }

        for (key, value) in [
            ("vectors.built_at", String(now)),
            ("vectors.dim", String(dim))
        ] {
            try db.execute(sql: """
                INSERT INTO meta (key, value) VALUES (?, ?)
                ON CONFLICT(key) DO UPDATE SET value = excluded.value
                """, arguments: [key, value])
        }

        return VectorBuildResult(
            noteCount: noteCount,
            dim: dim,
            builtAt: now,
            skipped: false,
            reason: ""
        )
    }

    // MARK: - Private
}

struct ExpandByVectorsTransaction: GRDBReadTransaction {
    // MARK: - Property
    let seedIds: [String]
    let limit: Int
    let excludeIds: Set<String>

    // MARK: - Initializer
    init(seedIds: [String], limit: Int = 10, excludeIds: Set<String> = []) {
        self.seedIds = seedIds
        self.limit = limit
        self.excludeIds = excludeIds
    }

    // MARK: - Public
    func perform(_ db: Database) throws -> [VectorHit] {
        guard !seedIds.isEmpty else { return [] }

        let vectors = try FetchNoteVectorsTransaction().perform(db)

        guard !vectors.isEmpty else { return [] }

        let seedVectors = seedIds.compactMap { id in vectors[id] }

        guard !seedVectors.isEmpty else { return [] }

        let dim = seedVectors[0].count
        var centroid = [Double](repeating: 0, count: dim)

        for vector in seedVectors {
            for index in 0..<min(dim, vector.count) { centroid[index] += Double(vector[index]) }
        }

        for index in 0..<dim { centroid[index] /= Double(seedVectors.count) }

        let centroidVector = centroid.map { value in Float(value) }
        var excluded = excludeIds
        excluded.formUnion(seedIds)

        let inactive = try Set(String.fetchAll(db, sql: """
            SELECT id FROM notes WHERE \(Policy.notSurface(""))
            """))
        excluded.formUnion(inactive)

        var scored: [(id: String, score: Double)] = []

        for (id, vector) in vectors where !excluded.contains(id) {
            let similarity = VectorMath.cosine(centroidVector, vector)

            if similarity > 0 { scored.append((id, similarity)) }
        }

        scored.sort { lhs, rhs in
            lhs.score != rhs.score ? lhs.score > rhs.score : lhs.id < rhs.id
        }

        let top = scored.prefix(limit)

        guard !top.isEmpty else { return [] }

        let ids = top.map { hit in hit.id }
        let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ",")
        let rows = try Row.fetchAll(db, sql: """
            SELECT id, axis, title, summary, path FROM notes
            WHERE id IN (\(placeholders)) AND \(Policy.surface(""))
            """, arguments: StatementArguments(ids))
        var metaById: [String: Row] = [:]

        for row in rows { metaById[row["id"] as String] = row }

        return top.compactMap { hit -> VectorHit? in
            guard let row = metaById[hit.id] else { return nil }

            return VectorHit(
                id: hit.id,
                axis: row["axis"],
                title: row["title"],
                summary: row["summary"] as String?,
                path: row["path"],
                score: hit.score
            )
        }
    }

    // MARK: - Private
}
