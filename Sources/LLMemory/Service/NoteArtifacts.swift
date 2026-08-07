//
//  NoteArtifacts.swift
//  LLMemory
//
//  Created by JSilver on 8/7/26.
//

import Foundation
import GRDB

public enum NoteArtifacts {
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
    
    public struct RouteArtifact: Encodable, Equatable, Sendable {
        enum CodingKeys: String, CodingKey {
            case type, kind, neighbor, term, namespace, key
        }
        
        // MARK: - Property
        public let type: String
        public let kind: String?
        public let neighbor: String?
        public let term: String?
        public let namespace: String?
        public let key: String?
        
        // MARK: - Initializer
        // MARK: - Public
        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            
            try container.encode(type, forKey: .type)
            
            if let kind { try container.encode(kind, forKey: .kind) }
            if let neighbor { try container.encode(neighbor, forKey: .neighbor) }
            if let term { try container.encode(term, forKey: .term) }
            if let namespace { try container.encode(namespace, forKey: .namespace) }
            if let key { try container.encode(key, forKey: .key) }
        }
        
        // MARK: - Private
    }
    
    // MARK: - Property
    static let identityTables = [
        "note_retrieval_terms", "note_meta", "ripple_flags", "note_usage",
        "candidate_dismissals", "note_source"
    ]
    static let historyTables = ["note_lifecycle_events"]
    
    static let tableDisposition: [String: Disposition] = [
        "tags": .reconstructable,
        "note_ref_markers": .reconstructable,
        "entity_index": .reconstructable,
        "note_links": .preserved,
        "note_retrieval_terms": .preserved,
        "note_meta": .preserved,
        "ripple_flags": .preserved,
        "note_lifecycle_events": .preserved,
        "note_usage": .preserved,
        "note_source": .preserved,
        "note_vectors": .acceptedLoss,
        "candidate_dismissals": .preserved
    ]
    
    static let tableSplitPolicy: [String: SplitPolicy] = [
        "tags": .rebuild,
        "note_ref_markers": .rebuild,
        "entity_index": .rebuild,
        "note_source": .rebuild,
        "note_vectors": .rebuild,
        "note_retrieval_terms": .routeRevalidate,
        "note_meta": .route,
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
        linkKindSplitPolicy.filter { entry in entry.value == .rebuild }.map { entry in entry.key }
    )
    
    static let routeLinkKinds: Set<String> = Set(
        linkKindSplitPolicy
            .filter { entry in entry.value == .route || entry.value == .routeRevalidate }
            .map { entry in entry.key }
    )
    
    // MARK: - Initializer
    // MARK: - Public
    static func noteCascadeTables(_ db: Database) throws -> [String] {
        let tables = try String.fetchAll(
            db,
            sql: "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'"
        )
        var cascading: [String] = []
        
        for table in tables {
            let foreignKeys = try Row.fetchAll(db, sql: "PRAGMA foreign_key_list(\(table))")
            let cascades = foreignKeys.contains { row in
                (row["table"] as String?) == "notes"
                    && ((row["on_delete"] as String?)?.uppercased().contains("CASCADE") ?? false)
            }
            
            if cascades { cascading.append(table) }
        }
        
        return cascading
    }
    
    static func reparent(_ db: Database, from: String, to: String) throws {
        guard from != to else { return }
        
        for table in identityTables + historyTables {
            try db.execute(sql: "DELETE FROM \(table) WHERE note_id = ?", arguments: [to])
            try db.execute(
                sql: "UPDATE \(table) SET note_id = ? WHERE note_id = ?",
                arguments: [to, from]
            )
        }
        
        try moveAuthoredLinks(db, from: from, to: to)
    }
    
    static func absorbForMerge(_ db: Database, from: String, into: String) throws {
        try db.execute(sql: """
            INSERT INTO note_usage (note_id, hit_count, last_retrieved_at, created_at)
            SELECT ?, f.hit_count, f.last_retrieved_at, f.created_at
            FROM note_usage f WHERE f.note_id = ?
            ON CONFLICT(note_id) DO UPDATE SET
                hit_count = hit_count + excluded.hit_count,
                last_retrieved_at = MAX(last_retrieved_at, excluded.last_retrieved_at)
            """, arguments: [into, from])
        
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
                """, arguments: [into, from])
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
                """, arguments: [into, from])
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
                """, arguments: [into, from])
        }
        
        let alreadyMerged = [
            "note_usage", "note_retrieval_terms", "ripple_flags",
            "candidate_dismissals", "note_source"
        ]
        
        for table in identityTables where !alreadyMerged.contains(table) {
            try db.execute(
                sql: "UPDATE OR IGNORE \(table) SET note_id = ? WHERE note_id = ?",
                arguments: [into, from]
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
            """, arguments: [from, from, into, from])
    }
    
    static func snapshotForRebuild(_ db: Database) throws {
        for table in identityTables + historyTables {
            try db.execute(sql: "DROP TABLE IF EXISTS \(stage(table))")
            try db.execute(sql: "CREATE TEMP TABLE \(stage(table)) AS SELECT * FROM \(table)")
        }
        
        do {
            let (notReconstructable, kinds) = notReconstructableClause("kind")
            
            try db.execute(sql: "DROP TABLE IF EXISTS \(stage("note_links_authored"))")
            try db.execute(
                sql: "CREATE TEMP TABLE \(stage("note_links_authored")) AS SELECT * FROM note_links WHERE \(notReconstructable)",
                arguments: StatementArguments(kinds)
            )
        }
        
        try db.execute(sql: "DROP TABLE IF EXISTS \(stage("entity_hits"))")
        try db.execute(sql: "CREATE TEMP TABLE \(stage("entity_hits")) AS SELECT entity, note_id, hit_count FROM entity_index")
    }
    
    static func restoreAfterRebuild(_ db: Database) throws {
        for table in identityTables + historyTables {
            try db.execute(sql: """
                INSERT OR REPLACE INTO \(table) SELECT * FROM \(stage(table))
                WHERE note_id IN (SELECT id FROM notes)
                """)
            try db.execute(sql: "DROP TABLE \(stage(table))")
        }
        
        try db.execute(sql: """
            INSERT OR IGNORE INTO note_links SELECT * FROM \(stage("note_links_authored"))
            WHERE src IN (SELECT id FROM notes) AND dst IN (SELECT id FROM notes)
            """)
        try db.execute(sql: "DROP TABLE \(stage("note_links_authored"))")
        try db.execute(sql: """
            UPDATE entity_index SET hit_count = s.hit_count
            FROM \(stage("entity_hits")) s
            WHERE entity_index.entity = s.entity AND entity_index.note_id = s.note_id
            """)
        try db.execute(sql: "DROP TABLE \(stage("entity_hits"))")
        
        let restored = try String.fetchAll(
            db,
            sql: "SELECT DISTINCT note_id FROM note_retrieval_terms WHERE status = 'active'"
        )
        
        for noteId in restored { try Notes.syncEnrich(db, noteId: noteId) }
    }
    
    static func splitRouteTargets(_ db: Database, noteId: String) throws -> [RouteArtifact] {
        var artifacts: [RouteArtifact] = []
        
        if !routeLinkKinds.isEmpty {
            let kinds = Array(routeLinkKinds)
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
                        term: nil,
                        namespace: nil,
                        key: nil
                    )
                )
            }
        }
        
        let routeTables = tableSplitPolicy
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
                            term: term,
                            namespace: nil,
                            key: nil
                        )
                    )
                }
            
            case "note_meta":
                let rows = try Row.fetchAll(
                    db,
                    sql: "SELECT namespace, key FROM note_meta WHERE note_id = ?",
                    arguments: [noteId]
                )
                
                for row in rows {
                    artifacts.append(
                        RouteArtifact(
                            type: "meta",
                            kind: nil,
                            neighbor: nil,
                            term: nil,
                            namespace: row["namespace"],
                            key: row["key"]
                        )
                    )
                }
            
            default:
                throw NSError(domain: "NoteArtifacts", code: 1, userInfo: [
                    NSLocalizedDescriptionKey:
                        "route-policy table '\(table)' has no identity handling in splitRouteTargets — add a case"
                ])
            }
        }
        
        return artifacts
    }
    
    // MARK: - Private
    private static func stage(_ table: String) -> String { "_rb_saved_\(table)" }
    
    private static func notReconstructableClause(
        _ column: String
    ) -> (clause: String, args: [String]) {
        let kinds = Array(reconstructableLinkKinds)
        let placeholders = kinds.map { _ in "?" }.joined(separator: ", ")
        
        return ("\(column) NOT IN (\(placeholders))", kinds)
    }
    
    private static func moveAuthoredLinks(_ db: Database, from: String, to: String) throws {
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
