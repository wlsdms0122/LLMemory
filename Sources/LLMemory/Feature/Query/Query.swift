//
//  Query.swift
//  LLMemory
//
//  Created by JSilver on 8/7/26.
//

import Foundation

public struct Query {
    // MARK: - Property
    let retrieval: RetrievalService
    let notes: NotesService
    let stats: StatsService
    let lint: LintService
    let enrichment: EnrichmentService
    let consolidate: ConsolidateService

    // MARK: - Initializer
    init(
        retrieval: RetrievalService,
        notes: NotesService,
        stats: StatsService,
        lint: LintService,
        enrichment: EnrichmentService,
        consolidate: ConsolidateService
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
        axis: String?,
        limit: Int,
        expand: Int,
        cliSessionId: String,
        includeStale: Bool,
        excludeAxes: [String],
        raw: Bool
    ) async throws -> (rows: [SearchRow], extra: [ExpandedNote]) {
        try await retrieval.search(
            query: query,
            axis: axis,
            limit: limit,
            expand: expand,
            cliSessionId: cliSessionId,
            includeStale: includeStale,
            excludeAxes: excludeAxes,
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

    public func metaById(
        noteId: String,
        namespace: String?
    ) async throws -> [String: [String: String]] {
        try await notes.metaById(noteId: noteId, namespace: namespace)
    }

    public func metaByKV(
        namespace: String,
        key: String,
        value: String?,
        limit: Int
    ) async throws -> [(noteId: String, value: String)] {
        try await notes.metaByKV(
            namespace: namespace,
            key: key,
            value: value,
            limit: limit
        )
    }

    public func entity(
        name: String?,
        limit: Int
    ) async throws -> [EntityHit] {
        try await retrieval.entity(name: name, limit: limit)
    }

    public func listAxes() async throws -> [AxisRow] {
        try await notes.listAxes()
    }

    public func structure(
        axis: String?
    ) async throws -> StructureResult {
        try await notes.structure(axis: axis)
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

    public func axisStats(
        axis: String
    ) async throws -> AxisStats {
        try await stats.axisStats(axis: axis)
    }

    public func overallStats() async throws -> OverallStats {
        try await stats.overallStats()
    }

    public func list(
        priority: String?,
        axis: String?,
        stale: Bool,
        sourceStale: Bool,
        limit: Int?
    ) async throws -> [NoteListRow] {
        try await notes.list(
            priority: priority,
            axis: axis,
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
    ) async throws -> [Lint.Issue] {
        try await lint.lint(
            id: id,
            code: code,
            severity: severity,
            limit: limit,
            includeDismissed: includeDismissed
        )
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

    // MARK: - Private
}
