//
//  AbsorbNoteArtifactsForMergeOperation.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct AbsorbNoteArtifactsForMergeOperation: GRDBOperation {
    // MARK: - Property
    typealias Parameter = (String, String)
    let from: String
    let into: String

    // MARK: - Initializer
    init(from: String, into: String) {
        self.from = from
        self.into = into
    }

    // MARK: - Public
    func execute(_ db: Database) throws {
        try db.execute(sql: """
            INSERT INTO note_usage (note_id, hit_count, last_retrieved_at, created_at)
            SELECT ?, f.hit_count, f.last_retrieved_at, f.created_at
            FROM note_usage f WHERE f.note_id = ?
            ON CONFLICT(note_id) DO UPDATE SET
                hit_count = hit_count + excluded.hit_count,
                last_retrieved_at = MAX(last_retrieved_at, excluded.last_retrieved_at)
            """, arguments: [into, self.from])
        
        do {
            let winnerIsFrom = """
                (CASE excluded.status WHEN 'active' THEN 2 WHEN 'pending' THEN 1 ELSE 0 END) >
                (CASE note_retrieval_terms.status WHEN 'active' THEN 2 WHEN 'pending' THEN 1 ELSE 0 END)
                """
            
            try db.execute(sql: """
                INSERT INTO note_retrieval_terms (note_id, kind, term, status, provenance, reject_reason, created_at, validated_at)
                SELECT ?, f.kind, f.term, f.status, f.provenance, f.reject_reason, f.created_at, f.validated_at
                FROM note_retrieval_terms f WHERE f.note_id = ?
                ON CONFLICT(note_id, kind, term) DO UPDATE SET
                    status = CASE WHEN (\(winnerIsFrom)) THEN excluded.status ELSE note_retrieval_terms.status END,
                    provenance = CASE WHEN (\(winnerIsFrom)) THEN excluded.provenance ELSE note_retrieval_terms.provenance END,
                    reject_reason = CASE WHEN (\(winnerIsFrom)) THEN excluded.reject_reason ELSE note_retrieval_terms.reject_reason END,
                    created_at = CASE WHEN (\(winnerIsFrom)) THEN excluded.created_at ELSE note_retrieval_terms.created_at END,
                    validated_at = CASE WHEN (\(winnerIsFrom)) THEN excluded.validated_at ELSE note_retrieval_terms.validated_at END
                """, arguments: [into, self.from])
        }
        
        do {
            let winnerIsFrom = """
                CASE
                    WHEN excluded.resolved_at IS NULL AND resolved_at IS NOT NULL THEN 1
                    WHEN excluded.resolved_at IS NOT NULL AND resolved_at IS NULL THEN 0
                    WHEN excluded.resolved_at IS NULL AND resolved_at IS NULL
                        THEN excluded.last_flagged_at > last_flagged_at
                    ELSE excluded.resolved_at > resolved_at
                END
                """
            
            try db.execute(sql: """
                INSERT INTO ripple_flags (note_id, flag, reason, created_at, last_flagged_at, flag_count, resolved_at)
                SELECT ?, f.flag, f.reason, f.created_at, f.last_flagged_at, f.flag_count, f.resolved_at
                FROM ripple_flags f WHERE f.note_id = ?
                ON CONFLICT(note_id, flag) DO UPDATE SET
                    created_at = MIN(created_at, excluded.created_at),
                    last_flagged_at = MAX(last_flagged_at, excluded.last_flagged_at),
                    flag_count = flag_count + excluded.flag_count,
                    resolved_at = CASE WHEN (\(winnerIsFrom)) THEN excluded.resolved_at ELSE resolved_at END,
                    reason = CASE WHEN (\(winnerIsFrom)) THEN excluded.reason ELSE reason END
                """, arguments: [into, self.from])
        }
        
        do {
            let winnerIsFrom = "excluded.last_dismissed_at > last_dismissed_at"
            
            try db.execute(sql: """
                INSERT INTO candidate_dismissals (note_id, kind, dismiss_count, word_count, section_count, generation, reason, last_dismissed_at)
                SELECT ?, f.kind, f.dismiss_count, f.word_count, f.section_count, f.generation, f.reason, f.last_dismissed_at
                FROM candidate_dismissals f WHERE f.note_id = ?
                ON CONFLICT(note_id, kind) DO UPDATE SET
                    dismiss_count = dismiss_count + excluded.dismiss_count,
                    last_dismissed_at = MAX(last_dismissed_at, excluded.last_dismissed_at),
                    word_count = CASE WHEN (\(winnerIsFrom)) THEN excluded.word_count ELSE word_count END,
                    section_count = CASE WHEN (\(winnerIsFrom)) THEN excluded.section_count ELSE section_count END,
                    generation = CASE WHEN (\(winnerIsFrom)) THEN excluded.generation ELSE generation END,
                    reason = CASE WHEN (\(winnerIsFrom)) THEN excluded.reason ELSE reason END
                """, arguments: [into, self.from])
        }
        
        let alreadyMerged = [
            "note_usage", "note_retrieval_terms", "ripple_flags",
            "candidate_dismissals", "note_source"
        ]
        
        for table in NoteArtifactPolicy.identityTables where !alreadyMerged.contains(table) {
            try db.execute(
                sql: "UPDATE OR IGNORE \(table) SET note_id = ? WHERE note_id = ?",
                arguments: [into, self.from]
            )
        }
        
        try db.execute(sql: """
            UPDATE entity_index SET
              hit_count = hit_count + COALESCE((
                SELECT f.hit_count FROM entity_index f
                WHERE f.note_id = ? AND f.entity = entity_index.entity), 0),
              last_seen_at = MAX(last_seen_at, COALESCE((
                SELECT f.last_seen_at FROM entity_index f
                WHERE f.note_id = ? AND f.entity = entity_index.entity), 0))
            WHERE note_id = ? AND entity IN (SELECT entity FROM entity_index WHERE note_id = ?)
            """, arguments: [self.from, self.from, into, self.from])
    }

    // MARK: - Private
}
