//
//  BuildVectorsTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct BuildVectorsTransaction: GRDBBrainTransaction {
    private let vectorMath = VectorMath()

    // MARK: - Initializer
    init() { }

    // MARK: - Public
    @discardableResult
    func perform(_ db: Database, _ brain: BrainContext) throws -> VectorBuildResult {
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

        let dim = min(brain.config.getInt("vectors.dim", default: 48), noteCount - 1)
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

        let ppmi = vectorMath.computePPMI(matrix, n: noteCount)
        let projection = try vectorMath.truncatedSVD(ppmi, n: noteCount, k: dim)

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
