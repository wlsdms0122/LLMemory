//
//  FetchSplitRouteTargetsOperation.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct FetchSplitRouteTargetsOperation: GRDBReadOperation {
    // MARK: - Property
    typealias Parameter = String
    let noteId: String

    // MARK: - Initializer
    init(noteId: String) {
        self.noteId = noteId
    }

    // MARK: - Public
    func execute(_ db: Database) throws -> [RouteArtifact] {
        var artifacts: [RouteArtifact] = []
        
        if !NoteArtifactPolicy.routeLinkKinds.isEmpty {
            let kinds = Array(NoteArtifactPolicy.routeLinkKinds)
            let placeholders = kinds.map { _ in "?" }.joined(separator: ", ")
            let rows = try Row.fetchAll(db, sql: """
                SELECT kind, CASE WHEN src = ? THEN dst ELSE src END AS neighbor
                FROM note_links
                WHERE (src = ? OR dst = ?) AND kind IN (\(placeholders))
                """, arguments: StatementArguments([noteId, noteId, noteId] + kinds))
            
            for row in rows {
                artifacts.append(
                    RouteArtifact(
                        type: "link",
                        kind: row["kind"],
                        neighbor: row["neighbor"],
                        term: nil
                    )
                )
            }
        }
        
        let routeTables = NoteArtifactPolicy.tableSplitPolicy
            .filter { entry in entry.value == .route || entry.value == .routeRevalidate }
            .keys
        
        for table in routeTables.sorted() {
            switch table {
            case "note_retrieval_terms":
                let terms = try String.fetchAll(
                    db,
                    sql: "SELECT term FROM note_retrieval_terms WHERE note_id = ? AND status = 'active'",
                    arguments: [noteId]
                )
                
                for term in terms {
                    artifacts.append(
                        RouteArtifact(
                            type: "term",
                            kind: nil,
                            neighbor: nil,
                            term: term
                        )
                    )
                }
            
            default:
                throw NSError(domain: "NoteArtifactPolicy", code: 1, userInfo: [
                    NSLocalizedDescriptionKey:
                        "route-policy table '\(table)' has no identity handling in splitRouteTargets — add a case"
                ])
            }
        }
        
        return artifacts
    }

    // MARK: - Private
}
