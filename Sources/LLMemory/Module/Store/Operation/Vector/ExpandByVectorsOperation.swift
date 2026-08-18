//
//  ExpandByVectorsOperation.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct ExpandByVectorsOperation: GRDBReadOperation {
    // MARK: - Property
    typealias Parameter = ([String], Int, Set<String>)
    let seedIds: [String]
    let limit: Int
    let excludeIds: Set<String>

    private let vectorMath = VectorMath()

    // MARK: - Initializer
    init(seedIds: [String], limit: Int = 10, excludeIds: Set<String> = []) {
        self.seedIds = seedIds
        self.limit = limit
        self.excludeIds = excludeIds
    }

    // MARK: - Public
    func execute(_ db: Database) throws -> [VectorHit] {
        guard !seedIds.isEmpty else { return [] }

        let vectors = try FetchNoteVectorsOperation().execute(db)

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
            let similarity = vectorMath.cosine(centroidVector, vector)

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
            SELECT id, title, summary FROM notes
            WHERE id IN (\(placeholders)) AND \(Policy.surface(""))
            """, arguments: StatementArguments(ids))
        var metaById: [String: Row] = [:]

        for row in rows { metaById[row["id"] as String] = row }

        return top.compactMap { hit -> VectorHit? in
            guard let row = metaById[hit.id] else { return nil }

            return VectorHit(
                id: hit.id,
                title: row["title"],
                summary: row["summary"] as String?,
                score: hit.score
            )
        }
    }

    // MARK: - Private
}
