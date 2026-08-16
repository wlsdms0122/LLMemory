//
//  RestoreArtifactsAfterRebuildTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct RestoreArtifactsAfterRebuildTransaction: GRDBTransaction {
    private let artifactPolicy = NoteArtifactPolicy()

    // MARK: - Initializer
    init() { }

    // MARK: - Public
    func perform(_ db: Database) throws {
        for table in NoteArtifactPolicy.identityTables + NoteArtifactPolicy.historyTables {
            try db.execute(sql: """
                INSERT OR REPLACE INTO \(table) SELECT * FROM \(artifactPolicy.stage(table))
                WHERE note_id IN (SELECT id FROM notes)
                """)
            try db.execute(sql: "DROP TABLE \(artifactPolicy.stage(table))")
        }
        
        try db.execute(sql: """
            INSERT OR IGNORE INTO note_links SELECT * FROM \(artifactPolicy.stage("note_links_authored"))
            WHERE src IN (SELECT id FROM notes) AND dst IN (SELECT id FROM notes)
            """)
        try db.execute(sql: "DROP TABLE \(artifactPolicy.stage("note_links_authored"))")
        try db.execute(sql: """
            UPDATE entity_index SET hit_count = s.hit_count
            FROM \(artifactPolicy.stage("entity_hits")) s
            WHERE entity_index.entity = s.entity AND entity_index.note_id = s.note_id
            """)
        try db.execute(sql: "DROP TABLE \(artifactPolicy.stage("entity_hits"))")
        
        let restored = try String.fetchAll(
            db,
            sql: "SELECT DISTINCT note_id FROM note_retrieval_terms WHERE status = 'active'"
        )
        
        for noteId in restored { try SyncNoteEnrichTransaction(noteId: noteId).perform(db) }
    }

    // MARK: - Private
}
