//
//  FetchProvenanceStatsOperation.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct FetchProvenanceStatsOperation: GRDBReadOperation {
    // MARK: - Property
    typealias Parameter = Double
    let disagreeFloor: Double

    private let vectorMath = VectorMath()

    // MARK: - Initializer
    init(disagreeFloor: Double) {
        self.disagreeFloor = disagreeFloor
    }

    // MARK: - Public
    func execute(_ db: Database) throws -> [EnrichmentStatus.ProvenanceStat] {
        let edges = try Row.fetchAll(db, sql: """
            SELECT src, dst, COALESCE(provenance, '(none)') AS prov
            FROM note_links WHERE kind = ?
            """, arguments: [LinkKind.assoc.rawValue])

        guard !edges.isEmpty else { return [] }

        let vectors = try FetchNoteVectorsOperation().execute(db)
        let floor = disagreeFloor
        var total: [String: Int] = [:]
        var disagree: [String: Int] = [:]

        for edge in edges {
            let provenance: String = edge["prov"]
            total[provenance, default: 0] += 1

            let src: String = edge["src"]
            let dst: String = edge["dst"]

            if let srcVector = vectors[src],
                let dstVector = vectors[dst],
                vectorMath.cosine(srcVector, dstVector) < floor {
                disagree[provenance, default: 0] += 1
            }
        }

        return total.keys.sorted().map { provenance in
            EnrichmentStatus.ProvenanceStat(
                provenance: provenance,
                assocEdges: total[provenance] ?? 0,
                disagreeEdges: disagree[provenance] ?? 0
            )
        }
    }

    // MARK: - Private
}
