//
//  SnapshotArtifactsForRebuildOperation.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct SnapshotArtifactsForRebuildOperation: GRDBOperation {
    // MARK: - Property
    typealias Parameter = Never

    private let artifactPolicy = NoteArtifactPolicy()

    // MARK: - Initializer
    init() { }

    // MARK: - Public
    func execute(_ db: Database) throws {
        for table in NoteArtifactPolicy.identityTables + NoteArtifactPolicy.historyTables {
            try db.execute(sql: "DROP TABLE IF EXISTS \(artifactPolicy.stage(table))")
            try db.execute(sql: "CREATE TEMP TABLE \(artifactPolicy.stage(table)) AS SELECT * FROM \(table)")
        }
        
        do {
            let (notReconstructable, kinds) = artifactPolicy.notReconstructableClause("kind")
            
            try db.execute(sql: "DROP TABLE IF EXISTS \(artifactPolicy.stage("note_links_authored"))")
            try db.execute(
                sql: "CREATE TEMP TABLE \(artifactPolicy.stage("note_links_authored")) AS SELECT * FROM note_links WHERE \(notReconstructable)",
                arguments: StatementArguments(kinds)
            )
        }
        
        try db.execute(sql: "DROP TABLE IF EXISTS \(artifactPolicy.stage("entity_hits"))")
        try db.execute(sql: "CREATE TEMP TABLE \(artifactPolicy.stage("entity_hits")) AS SELECT entity, note_id, hit_count FROM entity_index")
    }

    // MARK: - Private
}
