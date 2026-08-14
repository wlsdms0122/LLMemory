//
//  SnapshotArtifactsForRebuildTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct SnapshotArtifactsForRebuildTransaction: GRDBTransaction {
    // MARK: - Initializer
    init() { }

    // MARK: - Public
    func perform(_ db: Database) throws {
        for table in NoteArtifacts.identityTables + NoteArtifacts.historyTables {
            try db.execute(sql: "DROP TABLE IF EXISTS \(NoteArtifacts.stage(table))")
            try db.execute(sql: "CREATE TEMP TABLE \(NoteArtifacts.stage(table)) AS SELECT * FROM \(table)")
        }
        
        do {
            let (notReconstructable, kinds) = NoteArtifacts.notReconstructableClause("kind")
            
            try db.execute(sql: "DROP TABLE IF EXISTS \(NoteArtifacts.stage("note_links_authored"))")
            try db.execute(
                sql: "CREATE TEMP TABLE \(NoteArtifacts.stage("note_links_authored")) AS SELECT * FROM note_links WHERE \(notReconstructable)",
                arguments: StatementArguments(kinds)
            )
        }
        
        try db.execute(sql: "DROP TABLE IF EXISTS \(NoteArtifacts.stage("entity_hits"))")
        try db.execute(sql: "CREATE TEMP TABLE \(NoteArtifacts.stage("entity_hits")) AS SELECT entity, note_id, hit_count FROM entity_index")
    }

    // MARK: - Private
}
