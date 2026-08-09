//
//  EnrichmentReview.swift
//  LLMemory
//
//  Created by JSilver on 8/7/26.
//

import Foundation
import GRDB

public enum EnrichmentReview {
    public struct ReviewPass {
        // MARK: - Property
        public var flagged = 0
        public var resolved = 0
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    public struct ProvenanceStat {
        // MARK: - Property
        public let provenance: String
        public let assocEdges: Int
        public let disagreeEdges: Int
        
        public var disagreeRate: Double {
            assocEdges > 0 ? Double(disagreeEdges) / Double(assocEdges) : 0
        }
        
        public var alarm: Bool {
            disagreeRate > Config.getDouble("enrich.model_alarm_rate", default: 0.4)
        }
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    public struct Status {
        // MARK: - Property
        public let termCounts: [(kind: String, status: String, count: Int)]
        public let assocTotal: Int
        public let assocActive: Int
        public let assocDormant: Int
        public let vectorsBuiltAt: Int?
        public let vectorsDim: Int?
        public let noteCount: Int
        public let vectorCount: Int
        public let provenanceStats: [ProvenanceStat]
        public let reviewFlagged: Int
        
        public var vectorCoverage: Double {
            noteCount > 0 ? Double(vectorCount) / Double(noteCount) : 0
        }
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    // MARK: - Property
    static let flagKind = "enrich_review"
    
    // MARK: - Initializer
    // MARK: - Public
    @discardableResult
    static func flagDisagreements(_ db: Database, now: Int) throws -> ReviewPass {
        var pass = ReviewPass()
        let vectors = try loadVectors(db)
        
        guard !vectors.isEmpty else { return pass }
        
        let floor = Config.getDouble("enrich.disagree_floor", default: 0.15)
        let edges = try Row.fetchAll(db, sql: """
            SELECT src, dst, provenance FROM note_links WHERE kind = ?
            """, arguments: [Links.kindAssoc])
        var flagged = Set<String>()
        
        for edge in edges {
            let src: String = edge["src"]
            let dst: String = edge["dst"]
            
            guard let srcVector = vectors[src], let dstVector = vectors[dst] else { continue }
            
            let similarity = cosine(srcVector, dstVector)
            
            if similarity < floor {
                for noteId in [src, dst] {
                    try AddRippleFlagTransaction(
                        noteId: noteId,
                        kind: flagKind,
                        reason: "assoc edge \(src)↔\(dst) cosine \(String(format: "%.3f", similarity)) < floor \(String(format: "%.2f", floor))",
                        now: now
                    ).perform(db)
                    flagged.insert(noteId)
                }
            }
        }
        
        pass.flagged = flagged.count
        
        let open = try String.fetchAll(db, sql: """
            SELECT note_id FROM ripple_flags WHERE flag = ? AND resolved_at IS NULL
            """, arguments: [flagKind])
        
        for noteId in open where !flagged.contains(noteId) {
            pass.resolved += try ResolveRippleFlagTransaction(
                noteId: noteId,
                kind: flagKind,
                reason: "disagreement cleared (cosine recovered or edge pruned)",
                now: now
            ).perform(db)
        }
        
        return pass
    }
    
    static func provenanceStats(_ db: Database) throws -> [ProvenanceStat] {
        let edges = try Row.fetchAll(db, sql: """
            SELECT src, dst, COALESCE(provenance, '(none)') AS prov
            FROM note_links WHERE kind = ?
            """, arguments: [Links.kindAssoc])
        
        guard !edges.isEmpty else { return [] }
        
        let vectors = try loadVectors(db)
        let floor = Config.getDouble("enrich.disagree_floor", default: 0.15)
        var total: [String: Int] = [:]
        var disagree: [String: Int] = [:]
        
        for edge in edges {
            let provenance: String = edge["prov"]
            total[provenance, default: 0] += 1
            
            let src: String = edge["src"]
            let dst: String = edge["dst"]
            
            if let srcVector = vectors[src],
                let dstVector = vectors[dst],
                cosine(srcVector, dstVector) < floor {
                disagree[provenance, default: 0] += 1
            }
        }
        
        return total.keys.sorted().map { provenance in
            ProvenanceStat(
                provenance: provenance,
                assocEdges: total[provenance] ?? 0,
                disagreeEdges: disagree[provenance] ?? 0
            )
        }
    }
    
    static func status(_ db: Database) throws -> Status {
        let termRows = try Row.fetchAll(db, sql: """
            SELECT kind, status, COUNT(*) AS c FROM note_retrieval_terms
            GROUP BY kind, status ORDER BY kind, status
            """)
        let termCounts = termRows.map { row in
            (row["kind"] as String, row["status"] as String, row["c"] as Int)
        }
        let floor = Genome.double("links.neighbor_floor")
        let assocRow = try Row.fetchOne(db, sql: """
            SELECT COUNT(*) AS total,
                   COALESCE(SUM(CASE WHEN weight >= ? THEN 1 ELSE 0 END), 0) AS active
            FROM note_links WHERE kind = ?
            """, arguments: [floor, Links.kindAssoc])
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
            """, arguments: [flagKind]) ?? 0
        
        return Status(
            termCounts: termCounts,
            assocTotal: assocTotal,
            assocActive: assocActive,
            assocDormant: assocDormant,
            vectorsBuiltAt: builtAt,
            vectorsDim: dim,
            noteCount: noteCount,
            vectorCount: vectorCount,
            provenanceStats: try provenanceStats(db),
            reviewFlagged: reviewFlagged
        )
    }
    
    static func loadVectors(_ db: Database) throws -> [String: [Float]] {
        var vectors: [String: [Float]] = [:]
        let rows = try Row.fetchAll(db, sql: "SELECT note_id, dim, vec FROM note_vectors")
        
        for row in rows {
            let noteId: String = row["note_id"]
            let dim: Int = row["dim"]
            
            guard let data: Data = row["vec"],
                data.count == dim * MemoryLayout<Float>.size
            else {
                continue
            }
            
            vectors[noteId] = data.withUnsafeBytes { buffer in
                Array(buffer.bindMemory(to: Float.self))
            }
        }
        
        return vectors
    }
    
    static func cosine(_ lhs: [Float], _ rhs: [Float]) -> Double {
        guard lhs.count == rhs.count, !lhs.isEmpty else { return 0 }
        
        var dot = 0.0
        var lhsNorm = 0.0
        var rhsNorm = 0.0
        
        for index in 0..<lhs.count {
            dot += Double(lhs[index]) * Double(rhs[index])
            lhsNorm += Double(lhs[index]) * Double(lhs[index])
            rhsNorm += Double(rhs[index]) * Double(rhs[index])
        }
        
        if lhsNorm == 0 || rhsNorm == 0 { return 0 }
        
        return dot / (lhsNorm.squareRoot() * rhsNorm.squareRoot())
    }
    
    // MARK: - Private
}
