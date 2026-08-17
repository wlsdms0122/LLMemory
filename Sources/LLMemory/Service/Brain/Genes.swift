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
// (FetchGeneValueOperation), not this.
public struct Genes: Sendable {
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

    // This brain's committed genome state, warmed at boot and at the end of
    // every write scope, so it is never ahead of the database.
    private let cache: ParameterCache

    // The configuration this brain falls back to for a gene the genome has
    // no row for.
    private let config: Config

    // A candidate value that belongs to one execution rather than to the
    // brain. It is held here, in the value the execution was handed, so it
    // cannot be read by anyone who was not handed it — the shadow replay
    // borrows a genome, it does not change one.
    private let candidates: [String: Double]

    // MARK: - Initializer
    init(cache: ParameterCache, config: Config, candidates: [String: Double] = [:]) {
        self.cache = cache
        self.config = config
        self.candidates = candidates
    }

    // MARK: - Public
    // The catalogue is species-level — it ships with the binary and is the
    // same for every brain, so it answers without one.
    public static func gene(_ id: String) -> Gene? {
        catalog.first { gene in gene.id == id }
    }

    public func double(_ id: String) -> Double {
        guard let gene = Self.gene(id) else {
            assertionFailure("undeclared gene: \(id)")

            return config.getDouble(id, default: 0)
        }

        return resolve(gene, stored: cache.geneValue(id)).value
    }

    public func int(_ id: String) -> Int {
        Int(double(id).rounded())
    }

    public func source(_ id: String) -> String {
        guard let gene = Self.gene(id) else { return "config" }

        return resolve(gene, stored: cache.geneValue(id)).source
    }

    // Whether the catalog admits this value, answered once. Every caller
    // that decides admissibility asks here — the write operation, the op
    // that must refuse with a sentence before writing, and the shadow replay
    // that only borrows a value. Three copies of the same inequality drift
    // one bound at a time, and the copy that drifts is the one that refuses.
    static func rejection(
        _ id: String,
        value: Double?,
        requireMutable: Bool = false
    ) -> GenomeWriteError? {
        guard let gene = Self.gene(id) else { return .unknownGene(id) }

        if requireMutable && !gene.mutable { return .locked(id) }

        guard let value else { return nil }

        guard value >= gene.min && value <= gene.max else {
            return .outOfBounds(id, value, gene)
        }

        if gene.integer && value != value.rounded() { return .notInteger(id, value) }

        return nil
    }

    // The same genome answering one gene differently. Whoever holds this
    // value sees the candidate; whoever holds the original does not, which is
    // what keeps a replay from leaking into the brain it is measuring.
    func shadowing(_ id: String, _ value: Double) -> Genes {
        Genes(
            cache: cache,
            config: config,
            candidates: candidates.merging([id: value]) { _, new in new }
        )
    }

    // The one place a gene value is resolved, so "which value?" and "where
    // from?" cannot disagree. `stored` is the genome-table value — the warmed
    // cache for the readers above, an explicit snapshot for the list, which
    // reports committed state and must not consult a cache to do it. A
    // candidate belongs to this execution and outranks both.
    func resolve(_ gene: Gene, stored: Double?) -> (value: Double, source: String) {
        if let candidate = candidates[gene.id] { return (candidate, "shadow") }

        if let stored { return (stored, "genome") }

        let configured = config.getDouble(gene.id, default: gene.wildType)

        return (configured, configured == gene.wildType ? "wild_type" : "config")
    }

    // MARK: - Private
}
