//
//  Genome.swift
//  LLMemory
//
//  Created by JSilver on 8/7/26.
//

import Foundation
import GRDB

public enum Genome {
    public struct Gene: Sendable {
        // MARK: - Property
        public let id: String
        public let wildType: Double
        public let min: Double
        public let max: Double
        public let mutable: Bool
        public let integer: Bool
        public let summary: String
        
        // MARK: - Initializer
        init(
            id: String,
            wildType: Double,
            min: Double,
            max: Double,
            mutable: Bool,
            integer: Bool = false,
            summary: String
        ) {
            self.id = id
            self.wildType = wildType
            self.min = min
            self.max = max
            self.mutable = mutable
            self.integer = integer
            self.summary = summary
        }
        
        // MARK: - Public
        // MARK: - Private
    }
    
    enum WriteError: Error, CustomStringConvertible {
        case unknownGene(String)
        case outOfBounds(String, Double, Gene)
        case notInteger(String, Double)
        case locked(String)
        
        var description: String {
            switch self {
            case .unknownGene(let id):
                return "unknown gene: '\(id)' — see `genome list` for the catalog"
            
            case .outOfBounds(let id, let value, let gene):
                return "gene '\(id)' value \(value) is outside bounds [\(gene.min), \(gene.max)]"
            
            case .notInteger(let id, let value):
                return "gene '\(id)' takes whole numbers — got \(value)"
            
            case .locked(let id):
                return "gene '\(id)' is locked (write-path) — homeostasis may not adjust it"
            }
        }
    }
    
    public struct ListRow: Encodable {
        enum CodingKeys: String, CodingKey {
            case id, value
            case wildType = "wild_type"
            case min, max, mutable, source, summary
        }
        
        // MARK: - Property
        public let id: String
        public let value: Double
        public let wildType: Double
        public let min: Double
        public let max: Double
        public let mutable: Bool
        public let source: String
        public let summary: String
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    public struct HistoryRow: Encodable {
        enum CodingKeys: String, CodingKey {
            case geneId = "gene_id"
            case oldValue = "old_value"
            case newValue = "new_value"
            case cause, detail, ts
        }
        
        // MARK: - Property
        public let geneId: String
        public let oldValue: Double?
        public let newValue: Double
        public let cause: String
        public let detail: String?
        public let ts: Int
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    // MARK: - Property
    public static let catalog: [Gene] = [
        Gene(id: "links.sibling_rank_weight", wildType: 0.3, min: 0.0, max: 1.0, mutable: true,
             summary: "sibling 엣지의 연상 랭킹 발언권 (사실성은 1.0 유지)"),
        Gene(id: "priming.alpha", wildType: 0.5, min: 0.0, max: 2.0, mutable: true,
             summary: "최근 인출 축 prior 의 rerank 가중"),
        Gene(id: "priming.window_min", wildType: 120, min: 10, max: 1440, mutable: true, integer: true,
             summary: "priming prior 가 보는 최근 인출 창 (분)"),
        Gene(id: "related.similar_limit", wildType: 5, min: 2, max: 12, mutable: true, integer: true,
             summary: "related 의 similar/vector 확장 폭"),
        Gene(id: "related.expand_hops", wildType: 1, min: 0, max: 2, mutable: true, integer: true,
             summary: "related 의 링크 확장 hop 수"),
        Gene(id: "links.strengthen_step", wildType: 1.0, min: 0.1, max: 2.0, mutable: false,
             summary: "cooccur 강화 스텝 (구조 영구 변경)"),
        Gene(id: "links.decay_factor", wildType: 0.9, min: 0.5, max: 0.99, mutable: false,
             summary: "prune 틱의 학습 엣지 감쇠율"),
        Gene(id: "links.prune_floor", wildType: 0.3, min: 0.05, max: 0.5, mutable: false,
             summary: "감쇠 엣지 절단 바닥"),
        Gene(id: "links.neighbor_floor", wildType: 0.5, min: 0.1, max: 1.0, mutable: false,
             summary: "이웃 확장에 참여하는 최소 엣지 weight"),
        Gene(id: "links.proposed_initial_weight", wildType: 0.35, min: 0.1, max: 0.6, mutable: false,
             summary: "propose_link(assoc) 초기 weight"),
        Gene(id: "rebirth.default_factor", wildType: 1.1, min: 1.0, max: 1.3, mutable: false,
             summary: "재활성(rehearsal) 기본 배율"),
        Gene(id: "rebirth.related_boost", wildType: 0.1, min: 0.0, max: 0.3, mutable: false,
             summary: "related 동시 인출의 rank-가중 rebirth 계수"),
        Gene(id: "rebirth.search_boost", wildType: 0.05, min: 0.0, max: 0.3, mutable: false,
             summary: "search 동시 인출의 rank-가중 rebirth 계수 (related 의 절반 — 약한 증거)"),
        Gene(id: "candidates.missing_edge.vec_cos", wildType: 0.9, min: 0.5, max: 0.99, mutable: false,
             summary: "missing_edge 후보의 벡터 cosine 임계"),
        Gene(id: "candidates.missing_edge.fts_bm25", wildType: -70.0, min: -200.0, max: -10.0, mutable: false,
             summary: "missing_edge 후보의 cold-노트 bm25 임계"),
        Gene(id: "activation.window_gap_sec", wildType: 900, min: 60, max: 7200, mutable: false, integer: true,
             summary: "익명 활성화의 시간창 추정 gap (관측 정책 — 기록에 영구 반영)")
    ]
    
    nonisolated(unsafe) private static var cache: [String: Double] = [:]
    
    // MARK: - Initializer
    // MARK: - Public
    public static func gene(_ id: String) -> Gene? {
        catalog.first { gene in gene.id == id }
    }
    
    public static func double(_ id: String) -> Double {
        guard let gene = gene(id) else {
            assertionFailure("undeclared gene: \(id)")
            
            return Config.getDouble(id, default: 0)
        }
        
        if let cached = cache[id] { return cached }
        
        return Config.getDouble(id, default: gene.wildType)
    }
    
    public static func int(_ id: String) -> Int {
        Int(double(id).rounded())
    }
    
    public static func source(_ id: String) -> String {
        if cache[id] != nil { return "genome" }
        
        guard let gene = gene(id) else { return "config" }
        
        return Config.getDouble(id, default: gene.wildType) == gene.wildType
            ? "wild_type"
            : "config"
    }
    
    public static func list() -> [ListRow] {
        catalog.map { gene in
            ListRow(
                id: gene.id,
                value: double(gene.id),
                wildType: gene.wildType,
                min: gene.min,
                max: gene.max,
                mutable: gene.mutable,
                source: source(gene.id),
                summary: gene.summary
            )
        }
    }
    
    public static func history(
        _ db: Database,
        geneId: String?,
        limit: Int
    ) throws -> [HistoryRow] {
        var request = GenomeEventRecord
            .order(Column("ts").desc, Column("id").desc)
            .limit(limit)
        
        if let geneId {
            request = request.filter(Column("gene_id") == geneId)
        }
        
        return try request.fetchAll(db).map { event in
            HistoryRow(
                geneId: event.geneId,
                oldValue: event.oldValue,
                newValue: event.newValue,
                cause: event.cause,
                detail: event.detail,
                ts: event.ts
            )
        }
    }
    
    static func warmCache(_ queue: any DatabaseReader) {
        cache.removeAll()
        
        if let rows = try? queue.read({ db in
            try Row.fetchAll(db, sql: "SELECT gene_id, value FROM genome")
        }) {
            for row in rows { cache[row["gene_id"] as String] = row["value"] as Double }
        }
    }
    
    static func invalidateCache() { cache.removeAll() }
    
    static func withOverride<T>(
        _ id: String,
        _ value: Double,
        _ body: () throws -> T
    ) rethrows -> T {
        let prior = cache[id]
        cache[id] = value
        
        defer { cache[id] = prior }
        
        return try body()
    }
    
    @discardableResult
    static func set(
        _ db: Database,
        id: String,
        value: Double,
        cause: String,
        detail: String?,
        requireMutable: Bool,
        now: Int
    ) throws -> (old: Double, new: Double) {
        guard let gene = gene(id) else { throw WriteError.unknownGene(id) }
        
        if requireMutable && !gene.mutable { throw WriteError.locked(id) }
        
        guard value >= gene.min && value <= gene.max else {
            throw WriteError.outOfBounds(id, value, gene)
        }
        
        if gene.integer && value != value.rounded() {
            throw WriteError.notInteger(id, value)
        }
        
        let old = cache[id] ?? Config.getDouble(id, default: gene.wildType)
        
        try GenomeRecord(geneId: id, value: value, updatedAt: now).upsert(db)
        
        var event = GenomeEventRecord(
            geneId: id,
            oldValue: old,
            newValue: value,
            cause: cause,
            detail: detail,
            ts: now
        )
        try event.insert(db)
        
        cache[id] = value
        
        return (old, value)
    }
    
    @discardableResult
    static func reset(_ db: Database, id: String, cause: String, now: Int) throws -> Double {
        guard let gene = gene(id) else { throw WriteError.unknownGene(id) }
        
        let old = cache[id] ?? Config.getDouble(id, default: gene.wildType)
        
        _ = try GenomeRecord.deleteOne(db, key: id)
        
        var event = GenomeEventRecord(
            geneId: id,
            oldValue: old,
            newValue: gene.wildType,
            cause: cause,
            detail: "reset to wild-type",
            ts: now
        )
        try event.insert(db)
        
        cache[id] = nil
        
        return old
    }
    
    // MARK: - Private
}
