//
//  Genes.swift
//  LLMemory
//
//  Created by JSilver on 8/7/26.
//

import Foundation

// The plasticity-parameter substrate. The declaration (gene list, bounds,
// wild types) is code-owned and species-level; the per-brain current values
// live in the DB and reach this layer through a cache that is loaded from
// committed state — at boot and at the end of every write scope. The loader is
// its only writer, so it is never ahead of the database and a value that
// belongs to one execution rather than to the brain never lands in it.
//
// A caller that must read a value it is itself writing reads the row
// (FetchGeneValueTransaction), not this.
public enum Genes {
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

    // MARK: - Property
    public static let catalog: [Gene] = [
        Gene(id: "links.sibling_rank_weight", wildType: 0.3, min: 0.0, max: 1.0, mutable: true,
             summary: "sibling 엣지의 연상 랭킹 발언권 (사실성은 1.0 유지)"),
        Gene(id: "priming.alpha", wildType: 0.5, min: 0.0, max: 2.0, mutable: true,
             summary: "최근 인출 태그 prior 의 rerank 가중"),
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

    // The value cache lives on the bound brain's context.
    private static var cache: [String: Double] {
        get { BrainContext.resolved.genesCache }
        set { BrainContext.resolved.genesCache = newValue }
    }

    // A candidate value that belongs to one execution, not to the brain. The
    // shadow replay re-runs a logged query under a value the genome does not
    // hold, and a task-local is the only place that value can live without
    // being visible to whoever else is reading this brain at the time.
    @TaskLocal private static var candidates: [String: Double] = [:]

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

        return resolve(gene, stored: cache[id]).value
    }

    public static func int(_ id: String) -> Int {
        Int(double(id).rounded())
    }

    public static func source(_ id: String) -> String {
        guard let gene = gene(id) else { return "config" }

        return resolve(gene, stored: cache[id]).source
    }

    // Whether the catalog admits this value, answered once. Every caller
    // that decides admissibility asks here — the write transaction, the op
    // that must refuse with a sentence before writing, and the shadow replay
    // that only borrows a value. Three copies of the same inequality drift
    // one bound at a time, and the copy that drifts is the one that refuses.
    static func rejection(
        _ id: String,
        value: Double?,
        requireMutable: Bool = false
    ) -> GenomeWriteError? {
        guard let gene = gene(id) else { return .unknownGene(id) }

        if requireMutable && !gene.mutable { return .locked(id) }

        guard let value else { return nil }

        guard value >= gene.min && value <= gene.max else {
            return .outOfBounds(id, value, gene)
        }

        if gene.integer && value != value.rounded() { return .notInteger(id, value) }

        return nil
    }

    static func warm(_ values: [String: Double]) {
        cache = values
    }

    static func invalidateCache() { cache.removeAll() }

    static func withCandidate<T>(
        _ id: String,
        _ value: Double,
        _ body: () throws -> T
    ) rethrows -> T {
        try $candidates.withValue(candidates.merging([id: value]) { _, new in new }, operation: body)
    }

    // The one place a gene value is resolved, so "which value?" and "where
    // from?" cannot disagree. `stored` is the genome-table value — the cache
    // for the ambient readers above, an explicit snapshot for the list, which
    // reports committed state and must not consult a cache to do it. A
    // candidate belongs to this execution and outranks both.
    static func resolve(_ gene: Gene, stored: Double?) -> (value: Double, source: String) {
        if let candidate = candidates[gene.id] { return (candidate, "shadow") }

        if let stored { return (stored, "genome") }

        let configured = Config.getDouble(gene.id, default: gene.wildType)

        return (configured, configured == gene.wildType ? "wild_type" : "config")
    }

    // MARK: - Private
}
