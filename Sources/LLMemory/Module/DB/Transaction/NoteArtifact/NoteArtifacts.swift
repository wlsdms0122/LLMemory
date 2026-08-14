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
    
    static let linkKindSplitPolicy: [String: SplitPolicy] = [
        Links.kindAssoc: .route,
        Links.kindMergeAncestor: .drop,
        Links.kindSupersedes: .drop,
        Links.kindPromotedTo: .drop,
        Links.kindCooccur: .autoRedistribute,
        Links.kindReference: .rebuild,
        Links.kindSibling: .autoCopy
    ]
    
    static let reconstructableLinkKinds: Set<String> = Set(
        Self.linkKindSplitPolicy.filter { entry in entry.value == .rebuild }.map { entry in entry.key }
    )
    
    static let routeLinkKinds: Set<String> = Set(
        Self.linkKindSplitPolicy
            .filter { entry in entry.value == .route || entry.value == .routeRevalidate }
            .map { entry in entry.key }
    )
    
    // MARK: - Initializer
    // MARK: - Public

    

    

    

    

    

    
    // MARK: - Private
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
}
