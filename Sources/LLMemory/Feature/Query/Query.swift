//
//  Query.swift
//  LLMemory
//
//  Created by JSilver on 8/7/26.
//

import Foundation

public struct QueryFeature {
    // MARK: - Property
    let session: Session

    // MARK: - Initializer
    init(session: Session) {
        self.session = session
    }

    // MARK: - Public (domain surface — binds the session and delegates to the service)
    public func search(
        query: String,
        axis: String?,
        limit: Int,
        expand: Int,
        cliSessionId: String,
        includeStale: Bool,
        excludeAxes: [String],
        raw: Bool
    ) async throws -> (rows: [Search.SearchRow], extra: [Links.ExpandedNote]) {
        try await QueryService.search(
            session.storage,
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
    ) async throws -> Framing.RelatedResult {
        try await QueryService.related(
            session.storage,
            text: text,
            kind: kind,
            cliSessionId: cliSessionId,
            includeBodies: includeBodies
        )
    }

    public func get(
        ids: [String],
        cliSessionId: String = ""
    ) async throws -> (found: [Reads.GetNote], missing: [String]) {
        try await QueryService.get(session.storage, ids: ids, cliSessionId: cliSessionId)
    }

    public func getSections(
        id: String,
        sections: [String]
    ) async throws -> (note: Reads.GetNote, slices: [Reads.SectionSlice]) {
        try await QueryService.getSections(session.storage, id: id, sections: sections)
    }

    public func getBudget(
        id: String,
        budget: Int
    ) async throws -> (note: Reads.GetNote, cut: Reads.BudgetCut) {
        try await QueryService.getBudget(session.storage, id: id, budget: budget)
    }

    public func toc(
        id: String
    ) async throws -> (note: Reads.GetNote, entries: [Reads.TocEntry]) {
        try await QueryService.toc(session.storage, id: id)
    }

    public func template(
        id: String
    ) async throws -> (note: Reads.GetNote, frame: [Template.FrameNode]) {
        try await QueryService.template(session.storage, id: id)
    }

    public func metaById(
        noteId: String,
        namespace: String?
    ) async throws -> [String: [String: String]] {
        try await QueryService.metaById(session.storage, noteId: noteId, namespace: namespace)
    }

    public func metaByKV(
        namespace: String,
        key: String,
        value: String?,
        limit: Int
    ) async throws -> [(noteId: String, value: String)] {
        try await QueryService.metaByKV(
            session.storage,
            namespace: namespace,
            key: key,
            value: value,
            limit: limit
        )
    }

    public func entity(
        name: String?,
        limit: Int
    ) async throws -> [Reads.EntityHit] {
        try await QueryService.entity(session.storage, name: name, limit: limit)
    }

    public func listAxes() async throws -> [(axis: String, description: String?, count: Int)] {
        try await QueryService.listAxes(session.storage)
    }

    public func structure(
        axis: String?
    ) async throws -> Reads.StructureResult {
        try await QueryService.structure(session.storage, axis: axis)
    }

    public func neighbors(
        id: String,
        k: Int,
        cliSessionId: String = ""
    ) async throws -> [Candidates.NeighborScore] {
        try await QueryService.neighbors(session.storage, id: id, k: k, cliSessionId: cliSessionId)
    }

    public func noteStats(
        id: String
    ) async throws -> Stats.NoteStats? {
        try await QueryService.noteStats(session.storage, id: id)
    }

    public func axisStats(
        axis: String
    ) async throws -> Stats.AxisStats {
        try await QueryService.axisStats(session.storage, axis: axis)
    }

    public func overallStats() async throws -> Stats.OverallStats {
        try await QueryService.overallStats(session.storage)
    }

    public func list(
        priority: String?,
        axis: String?,
        stale: Bool,
        sourceStale: Bool,
        limit: Int?
    ) async throws -> [Reads.ListRow] {
        try await QueryService.list(
            session.storage,
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
    ) async throws -> [Reads.HistoryEvent] {
        try await QueryService.history(session.storage, noteId: noteId, limit: limit)
    }

    public func lint(
        id: String? = nil,
        code: String? = nil,
        severity: String? = nil,
        limit: Int? = nil,
        includeDismissed: Bool = false
    ) async throws -> [Lint.Issue] {
        try await QueryService.lint(
            session.storage,
            id: id,
            code: code,
            severity: severity,
            limit: limit,
            includeDismissed: includeDismissed
        )
    }

    public func enrichment() async throws -> EnrichmentReview.Status {
        try await QueryService.enrichment(session.storage)
    }

    public func candidates(
        kinds: [String],
        limit: Int
    ) async throws -> [String: Candidates.Batch] {
        try await QueryService.candidates(session.storage, kinds: kinds, limit: limit)
    }

    // MARK: - Private
}
