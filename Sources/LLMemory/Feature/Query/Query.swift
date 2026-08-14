//
//  Query.swift
//  LLMemory
//
//  Created by JSilver on 8/7/26.
//

import Foundation

public struct Query {
    // MARK: - Property
    let retrieval: any RetrievalServiceable
    let notes: any NotesServiceable
    let stats: any StatsServiceable
    let lint: any LintServiceable
    let enrichment: any EnrichmentServiceable
    let consolidate: any ConsolidateServiceable

    // MARK: - Initializer
    init(
        retrieval: any RetrievalServiceable,
        notes: any NotesServiceable,
        stats: any StatsServiceable,
        lint: any LintServiceable,
        enrichment: any EnrichmentServiceable,
        consolidate: any ConsolidateServiceable
    ) {
        self.retrieval = retrieval
        self.notes = notes
        self.stats = stats
        self.lint = lint
        self.enrichment = enrichment
        self.consolidate = consolidate
    }

    // MARK: - Public (domain surface — delegates to the injected services)
    public func search(
        query: String,
        tags: [String],
        limit: Int,
        expand: Int,
        cliSessionId: String,
        includeStale: Bool,
        excludeTags: [String],
        raw: Bool
    ) async throws -> (rows: [SearchRow], extra: [ExpandedNote]) {
        try await retrieval.search(
            query: query,
            tags: tags,
            limit: limit,
            expand: expand,
            cliSessionId: cliSessionId,
            includeStale: includeStale,
            excludeTags: excludeTags,
            raw: raw
        )
    }

    public func related(
        text: String,
        kind: String?,
        cliSessionId: String,
        includeBodies: Bool
    ) async throws -> RelatedResult {
        try await retrieval.related(
            text: text,
            kind: kind,
            cliSessionId: cliSessionId,
            includeBodies: includeBodies
        )
    }

    public func get(
        ids: [String],
        cliSessionId: String = ""
    ) async throws -> (found: [NoteView], missing: [String]) {
        try await notes.get(ids: ids, cliSessionId: cliSessionId)
    }

    public func getSections(
        id: String,
        sections: [String],
        cliSessionId: String = ""
    ) async throws -> (note: NoteView, slices: [SectionSlice]) {
        try await notes.getSections(
            id: id,
            sections: sections,
            cliSessionId: cliSessionId
        )
    }

    public func getBudget(
        id: String,
        budget: Int,
        cliSessionId: String = ""
    ) async throws -> (note: NoteView, cut: BudgetCut) {
        try await notes.getBudget(
            id: id,
            budget: budget,
            cliSessionId: cliSessionId
        )
    }

    public func toc(
        id: String,
        cliSessionId: String = ""
    ) async throws -> (note: NoteView, entries: [TocEntry]) {
        try await notes.toc(id: id, cliSessionId: cliSessionId)
    }

    public func template(
        id: String,
        cliSessionId: String = ""
    ) async throws -> (note: NoteView, frame: [TemplateFrameNode]) {
        try await notes.template(id: id, cliSessionId: cliSessionId)
    }

    public func entity(
        name: String?,
        limit: Int
    ) async throws -> [EntityHit] {
        try await retrieval.entity(name: name, limit: limit)
    }

    public func tree(prefix: String?) async throws -> [TreeRow] {
        try await notes.tree(prefix: prefix)
    }

    public func structure(
        prefix: String?
    ) async throws -> StructureResult {
        try await notes.structure(prefix: prefix)
    }

    public func neighbors(
        id: String,
        k: Int,
        cliSessionId: String = ""
    ) async throws -> [NeighborScore] {
        try await retrieval.neighbors(id: id, k: k, cliSessionId: cliSessionId)
    }

    public func noteStats(
        id: String
    ) async throws -> NoteStats? {
        try await stats.noteStats(id: id)
    }

    public func prefixStats(
        prefix: String
    ) async throws -> PrefixStats {
        try await stats.prefixStats(prefix: prefix)
    }

    public func overallStats() async throws -> OverallStats {
        try await stats.overallStats()
    }

    public func list(
        priority: String?,
        tags: [String],
        fields: [NoteFieldFilter],
        stale: Bool,
        sourceStale: Bool,
        limit: Int?
    ) async throws -> [NoteListRow] {
        try await notes.list(
            priority: priority,
            tags: tags,
            fields: fields,
            stale: stale,
            sourceStale: sourceStale,
            limit: limit
        )
    }

    public func history(
        noteId: String,
        limit: Int
    ) async throws -> [NoteHistoryEvent] {
        try await notes.history(noteId: noteId, limit: limit)
    }

    public func lint(
        id: String? = nil,
        code: String? = nil,
        severity: String? = nil,
        limit: Int? = nil,
        includeDismissed: Bool = false
    ) async throws -> [LintIssue] {
        try await lint.lint(
            id: id,
            code: code,
            severity: severity,
            limit: limit,
            includeDismissed: includeDismissed
        )
    }

    // The rule vocabulary, beside the findings it explains — `query lint --rules`
    // asks what may be reported before anything is reported.
    public func lintRuleCatalog() -> [LintRuleInfo] {
        lint.ruleCatalog()
    }

    public func enrichment() async throws -> EnrichmentStatus {
        try await enrichment.status()
    }

    public func candidates(
        kinds: [String],
        limit: Int
    ) async throws -> [String: CandidateBatch] {
        try await consolidate.candidates(kinds: kinds, limit: limit)
    }

    // The vocabulary of `candidates(kinds:)`, beside the call it constrains —
    // a surface that validates its own argument needs the accepted set from
    // the same facade it asks, not from a service type it cannot otherwise see.
    public var candidateRetrievalKinds: [String] { consolidate.candidateRetrievalKinds }

    public var candidateStructuralKinds: [String] { consolidate.candidateStructuralKinds }

    public var candidateValidKinds: [String] { consolidate.candidateValidKinds }

    // MARK: - Private
}
