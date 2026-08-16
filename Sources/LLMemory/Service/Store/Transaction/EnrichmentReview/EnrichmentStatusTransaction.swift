//
//  EnrichmentStatusTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct EnrichmentStatusTransaction: GRDBReadTransaction {
    // MARK: - Property
    let neighborFloor: Double
    let enrichment: EnrichmentTuning

    // MARK: - Initializer
    init(neighborFloor: Double, enrichment: EnrichmentTuning) {
        self.neighborFloor = neighborFloor
        self.enrichment = enrichment
    }

    // MARK: - Public
    func perform(_ db: Database) throws -> EnrichmentStatus {
        let termRows = try Row.fetchAll(db, sql: """
            SELECT kind, status, COUNT(*) AS c FROM note_retrieval_terms
            GROUP BY kind, status ORDER BY kind, status
            """)
        let termCounts = termRows.map { row in
            (row["kind"] as String, row["status"] as String, row["c"] as Int)
        }
        let floor = neighborFloor
        let assocRow = try Row.fetchOne(db, sql: """
            SELECT COUNT(*) AS total,
                   COALESCE(SUM(CASE WHEN weight >= ? THEN 1 ELSE 0 END), 0) AS active
            FROM note_links WHERE kind = ?
            """, arguments: [floor, LinkKind.assoc.rawValue])
        let assocTotal = assocRow?["total"] as Int? ?? 0
        let assocActive = assocRow?["active"] as Int? ?? 0
        let assocDormant = assocTotal - assocActive
        let builtAt = try Int.fetchOne(
            db,
            sql: "SELECT CAST(value AS INTEGER) FROM meta WHERE key = 'vectors.built_at'"
        )
        let dim = try Int.fetchOne(
            db,
            sql: "SELECT CAST(value AS INTEGER) FROM meta WHERE key = 'vectors.dim'"
        )
        let noteCount = try Int.fetchOne(
            db,
            sql: "SELECT COUNT(*) FROM notes n WHERE \(Policy.surface())"
        ) ?? 0
        let vectorCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM note_vectors") ?? 0
        let reviewFlagged = try Int.fetchOne(db, sql: """
            SELECT COUNT(*) FROM ripple_flags WHERE flag = ? AND resolved_at IS NULL
            """, arguments: [EnrichmentReview.flagKind]) ?? 0

        return EnrichmentStatus(
            termCounts: termCounts,
            assocTotal: assocTotal,
            assocActive: assocActive,
            assocDormant: assocDormant,
            vectorsBuiltAt: builtAt,
            vectorsDim: dim,
            noteCount: noteCount,
            vectorCount: vectorCount,
            provenanceStats: try FetchProvenanceStatsTransaction(
                disagreeFloor: enrichment.disagreeFloor
            )
                .perform(db),
            reviewFlagged: reviewFlagged,
            modelAlarmRate: enrichment.modelAlarmRate
        )
    }

    // MARK: - Private
}
