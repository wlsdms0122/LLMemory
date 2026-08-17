//
//  PurgeEnrichmentProvenanceOperation.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct PurgeEnrichmentProvenanceOperation: GRDBOperation {
    // MARK: - Property
    let provenance: String
    let now: Int

    // MARK: - Initializer
    init(provenance: String, now: Int) {
        self.provenance = provenance
        self.now = now
    }

    // MARK: - Public
    func execute(_ db: Database) throws -> (termsPurged: Int, edgesPurged: Int, affected: [String]) {
        let affected = try String.fetchAll(db, sql: """
            SELECT DISTINCT note_id FROM note_retrieval_terms
            WHERE provenance = ? AND status != 'rejected'
            """, arguments: [provenance])

        try db.execute(sql: """
            UPDATE note_retrieval_terms
            SET status = 'rejected', reject_reason = 'purged', validated_at = ?
            WHERE provenance = ? AND status != 'rejected'
            """, arguments: [now, provenance])

        let termsPurged = db.changesCount

        try db.execute(sql: "DELETE FROM note_links WHERE provenance = ?", arguments: [provenance])

        let edgesPurged = db.changesCount

        for noteId in affected {
            try SyncNoteEnrichOperation(noteId: noteId).execute(db)
        }

        return (termsPurged, edgesPurged, affected)
    }

    // MARK: - Private
}
