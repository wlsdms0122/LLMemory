//
//  NoteArtifacts.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

public struct NoteArtifacts: Sendable {
    enum Disposition {
        case reconstructable
        case preserved
        case acceptedLoss
    }
    
    enum SplitPolicy {
        case rebuild
        case drop
        case route
        case routeRevalidate
        case autoRedistribute
        case autoCopy
    }
    
    // MARK: - Property
    static let identityTables = [
        "note_retrieval_terms", "ripple_flags", "note_usage",
        "candidate_dismissals", "note_source"
    ]
    static let historyTables = ["note_lifecycle_events"]
    
    static let tableDisposition: [String: Disposition] = [
        "tags": .reconstructable,
        "note_extra": .reconstructable,
        "note_ref_markers": .reconstructable,
        "entity_index": .reconstructable,
        "note_links": .preserved,
        "note_retrieval_terms": .preserved,
        "ripple_flags": .preserved,
        "note_lifecycle_events": .preserved,
        "note_usage": .preserved,
        "note_source": .preserved,
        "note_vectors": .acceptedLoss,
        "candidate_dismissals": .preserved
    ]
    
    static let tableSplitPolicy: [String: SplitPolicy] = [
        "tags": .rebuild,
        "note_extra": .rebuild,
        "note_ref_markers": .rebuild,
        "entity_index": .rebuild,
        "note_source": .rebuild,
        "note_vectors": .rebuild,
        "note_retrieval_terms": .routeRevalidate,
        "ripple_flags": .drop,
        "note_usage": .drop,
        "candidate_dismissals": .drop,
        "note_lifecycle_events": .drop
    ]
    
    static let reconstructableLinkKinds: Set<String> = Set(
        LinkKind.rawValues { kind in splitPolicy(for: kind) == .rebuild }
    )
    
    static let routeLinkKinds: Set<String> = Set(
        LinkKind.rawValues { kind in
            let policy = splitPolicy(for: kind)
            
            return policy == .route || policy == .routeRevalidate
        }
    )
    
    // MARK: - Initializer
    // MARK: - Public
    // What becomes of an edge of this kind when the note under it splits.
    // A switch rather than a table: a new kind is a new split decision, and
    // this is where not having made it stops compiling.
    static func splitPolicy(for kind: LinkKind) -> SplitPolicy {
        switch kind {
        case .assoc: .route
        case .mergeAncestor, .supersedes, .promotedTo: .drop
        case .cooccur: .autoRedistribute
        case .reference: .rebuild
        case .sibling: .autoCopy
        }
    }
    
    func stage(_ table: String) -> String { "_rb_saved_\(table)" }
    
    func notReconstructableClause(
        _ column: String
    ) -> (clause: String, args: [String]) {
        let kinds = Array(Self.reconstructableLinkKinds)
        let placeholders = kinds.map { _ in "?" }.joined(separator: ", ")
        
        return ("\(column) NOT IN (\(placeholders))", kinds)
    }
    
    func moveAuthoredLinks(_ db: Database, from: String, to: String) throws {
        let (notReconstructable, kinds) = notReconstructableClause("kind")
        
        try db.execute(
            sql: "UPDATE OR IGNORE note_links SET src = ? WHERE src = ? AND \(notReconstructable)",
            arguments: StatementArguments([to, from] + kinds)
        )
        try db.execute(
            sql: "UPDATE OR IGNORE note_links SET dst = ? WHERE dst = ? AND \(notReconstructable)",
            arguments: StatementArguments([to, from] + kinds)
        )
    }

    // MARK: - Private
}
