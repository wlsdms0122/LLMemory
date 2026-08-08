//
//  Query.swift
//  LLMemory
//
//  Created by JSilver on 8/7/26.
//

import Foundation
import GRDB
import Storage

public struct QueryFeature {
    // MARK: - Property
    
    let session: Session

    // MARK: - Initializer
    init(session: Session) {
        self.session = session
    }

    // MARK: - Public

    // MARK: - Public (domain surface — configures the session and runs the matching transaction)
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
        let outcome = try await session.storage.run(
            SearchNotesTransaction(
                .init(
                    query: query,
                    axis: axis,
                    limit: limit,
                    expand: expand,
                    cliSessionId: cliSessionId,
                    includeStale: includeStale,
                    excludeAxes: excludeAxes,
                    raw: raw
                )
            )
        )
        
        try? await session.storage.run(RecordRetrievalTransaction(outcome.record))
        
        return (outcome.rows, outcome.extra)
    }

    public func related(
        text: String,
        kind: String?,
        cliSessionId: String,
        includeBodies: Bool
    ) async throws -> Framing.RelatedResult {
        let outcome = try await session.storage.run(
            RelatedNotesTransaction(
                .init(
                    text: text,
                    kind: kind,
                    cliSessionId: cliSessionId,
                    includeBodies: includeBodies
                )
            )
        )
        
        try? await session.storage.run(RecordRetrievalTransaction(outcome.record))
        
        return outcome.result
    }

    public func get(
        ids: [String],
        cliSessionId: String = ""
    ) async throws -> (found: [Reads.GetNote], missing: [String]) {
        let outcome = try await session.storage.run(
            GetNotesTransaction(
                .init(
                    ids: ids,
                    cliSessionId: cliSessionId
                )
            )
        )
        
        if let record = outcome.record {
            try? await session.storage.run(RecordRetrievalTransaction(record))
        }
        
        return (outcome.found, outcome.missing)
    }

    public func getSections(
        id: String,
        sections: [String]
    ) async throws -> (note: Reads.GetNote, slices: [Reads.SectionSlice]) {
        try await session.storage.run(
            GetSectionsTransaction(
                .init(
                    id: id,
                    sections: sections
                )
            )
        )
    }

    public func getBudget(
        id: String,
        budget: Int
    ) async throws -> (note: Reads.GetNote, cut: Reads.BudgetCut) {
        try await session.storage.run(
            GetBudgetTransaction(
                .init(
                    id: id,
                    budget: budget
                )
            )
        )
    }

    public func toc(
        id: String
    ) async throws -> (note: Reads.GetNote, entries: [Reads.TocEntry]) {
        try await session.storage.run(
            NoteTocTransaction(
                .init(
                    id: id
                )
            )
        )
    }

    public func template(
        id: String
    ) async throws -> (note: Reads.GetNote, frame: [Template.FrameNode]) {
        try await session.storage.run(
            TemplateFrameTransaction(
                .init(
                    id: id
                )
            )
        )
    }

    public func metaById(
        noteId: String,
        namespace: String?
    ) async throws -> [String: [String: String]] {
        try await session.storage.run(
            NoteMetaByIdTransaction(
                .init(
                    noteId: noteId,
                    namespace: namespace
                )
            )
        )
    }

    public func metaByKV(
        namespace: String,
        key: String,
        value: String?,
        limit: Int
    ) async throws -> [(noteId: String, value: String)] {
        try await session.storage.run(
            NoteMetaByKVTransaction(
                .init(
                    namespace: namespace,
                    key: key,
                    value: value,
                    limit: limit
                )
            )
        )
    }

    public func entity(
        name: String?,
        limit: Int
    ) async throws -> [Reads.EntityHit] {
        try await session.storage.run(
            EntityNotesTransaction(
                .init(
                    name: name,
                    limit: limit
                )
            )
        )
    }

    public func listAxes() async throws -> [(axis: String, description: String?, count: Int)] {
        try await session.storage.run(ListAxesTransaction())
    }

    public func structure(
        axis: String?
    ) async throws -> Reads.StructureResult {
        try await session.storage.run(
            StructureReportTransaction(
                .init(
                    axis: axis
                )
            )
        )
    }

    public func neighbors(
        id: String,
        k: Int,
        cliSessionId: String = ""
    ) async throws -> [Candidates.NeighborScore] {
        let outcome = try await session.storage.run(
            NeighborsTransaction(
                .init(
                    id: id,
                    k: k,
                    cliSessionId: cliSessionId
                )
            )
        )
        
        if let record = outcome.record {
            try? await session.storage.run(RecordRetrievalTransaction(record))
        }
        
        return outcome.scores
    }

    public func noteStats(
        id: String
    ) async throws -> Stats.NoteStats? {
        try await session.storage.run(
            NoteStatsTransaction(
                .init(
                    id: id
                )
            )
        )
    }

    public func axisStats(
        axis: String
    ) async throws -> Stats.AxisStats {
        try await session.storage.run(
            AxisStatsTransaction(
                .init(
                    axis: axis
                )
            )
        )
    }

    public func overallStats() async throws -> Stats.OverallStats {
        try await session.storage.run(OverallStatsTransaction())
    }

    public func list(
        priority: String?,
        axis: String?,
        stale: Bool,
        sourceStale: Bool,
        limit: Int?
    ) async throws -> [Reads.ListRow] {
        try await session.storage.run(
            ListNotesTransaction(
                .init(
                    priority: priority,
                    axis: axis,
                    stale: stale,
                    sourceStale: sourceStale,
                    limit: limit
                )
            )
        )
    }

    public func history(
        noteId: String,
        limit: Int
    ) async throws -> [Reads.HistoryEvent] {
        try await session.storage.run(
            NoteHistoryTransaction(
                .init(
                    noteId: noteId,
                    limit: limit
                )
            )
        )
    }

    public func lint(
        id: String? = nil,
        code: String? = nil,
        severity: String? = nil,
        limit: Int? = nil,
        includeDismissed: Bool = false
    ) async throws -> [Lint.Issue] {
        try await session.storage.run(
            LintTransaction(
                .init(
                    id: id,
                    code: code,
                    severity: severity,
                    limit: limit,
                    includeDismissed: includeDismissed
                )
            )
        )
    }

    public func enrichment() async throws -> EnrichmentReview.Status {
        try await session.storage.run(EnrichmentStatusTransaction())
    }

    public func candidates(
        kinds: [String],
        limit: Int
    ) async throws -> [String: Candidates.Batch] {
        try await session.storage.run(
            CandidatesTransaction(
                .init(
                    kinds: kinds,
                    limit: limit
                )
            )
        )
    }

    // MARK: - Private
}
