//
//  QueryService.swift
//  LLMemory
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import Storage

// Read-domain service — runs the matching read transaction and applies the
// derived retrieval side effects. Surfaces call these methods; nothing above
// this tier runs a transaction itself.
public enum QueryService {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Public
    public static func search(
        _ storage: GRDBStorage,
        query: String,
        axis: String?,
        limit: Int,
        expand: Int,
        cliSessionId: String,
        includeStale: Bool,
        excludeAxes: [String],
        raw: Bool
    ) async throws -> (rows: [Search.SearchRow], extra: [Links.ExpandedNote]) {
        let outcome = try await storage.run(
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

        try await applyRecord(storage, outcome.record)

        return (outcome.rows, outcome.extra)
    }

    public static func related(
        _ storage: GRDBStorage,
        text: String,
        kind: String?,
        cliSessionId: String,
        includeBodies: Bool
    ) async throws -> Framing.RelatedResult {
        let outcome = try await storage.run(
            RelatedNotesTransaction(
                .init(
                    text: text,
                    kind: kind,
                    cliSessionId: cliSessionId,
                    includeBodies: includeBodies
                )
            )
        )

        let degraded = try await applyRecord(storage, outcome.record)

        guard !degraded.isEmpty else { return outcome.result }

        var snapshot = outcome.result.snapshot
        snapshot.degraded.append(contentsOf: degraded)

        return Framing.RelatedResult(snapshot: snapshot, bodies: outcome.result.bodies)
    }

    public static func get(
        _ storage: GRDBStorage,
        ids: [String],
        cliSessionId: String = ""
    ) async throws -> (found: [Reads.GetNote], missing: [String]) {
        let outcome = try await storage.run(
            GetNotesTransaction(
                .init(
                    ids: ids,
                    cliSessionId: cliSessionId
                )
            )
        )

        try await applyRecord(storage, outcome.record)

        return (outcome.found, outcome.missing)
    }

    public static func getSections(
        _ storage: GRDBStorage,
        id: String,
        sections: [String]
    ) async throws -> (note: Reads.GetNote, slices: [Reads.SectionSlice]) {
        let outcome = try await storage.run(
            GetSectionsTransaction(
                .init(
                    id: id,
                    sections: sections
                )
            )
        )

        try await applyRecord(storage, outcome.record)

        return (outcome.note, outcome.slices)
    }

    public static func getBudget(
        _ storage: GRDBStorage,
        id: String,
        budget: Int
    ) async throws -> (note: Reads.GetNote, cut: Reads.BudgetCut) {
        let outcome = try await storage.run(
            GetBudgetTransaction(
                .init(
                    id: id,
                    budget: budget
                )
            )
        )

        try await applyRecord(storage, outcome.record)

        return (outcome.note, outcome.cut)
    }

    public static func toc(
        _ storage: GRDBStorage,
        id: String
    ) async throws -> (note: Reads.GetNote, entries: [Reads.TocEntry]) {
        let outcome = try await storage.run(NoteTocTransaction(.init(id: id)))

        try await applyRecord(storage, outcome.record)

        return (outcome.note, outcome.entries)
    }

    public static func template(
        _ storage: GRDBStorage,
        id: String
    ) async throws -> (note: Reads.GetNote, frame: [Template.FrameNode]) {
        let outcome = try await storage.run(TemplateFrameTransaction(.init(id: id)))

        try await applyRecord(storage, outcome.record)

        return (outcome.note, outcome.frame)
    }

    public static func metaById(
        _ storage: GRDBStorage,
        noteId: String,
        namespace: String?
    ) async throws -> [String: [String: String]] {
        try await storage.run(
            NoteMetaByIdTransaction(
                .init(
                    noteId: noteId,
                    namespace: namespace
                )
            )
        )
    }

    public static func metaByKV(
        _ storage: GRDBStorage,
        namespace: String,
        key: String,
        value: String?,
        limit: Int
    ) async throws -> [(noteId: String, value: String)] {
        try await storage.run(
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

    public static func entity(
        _ storage: GRDBStorage,
        name: String?,
        limit: Int
    ) async throws -> [Reads.EntityHit] {
        try await storage.run(
            EntityNotesTransaction(
                .init(
                    name: name,
                    limit: limit
                )
            )
        )
    }

    public static func listAxes(
        _ storage: GRDBStorage
    ) async throws -> [(axis: String, description: String?, count: Int)] {
        try await storage.run(ListAxesTransaction())
    }

    public static func structure(
        _ storage: GRDBStorage,
        axis: String?
    ) async throws -> Reads.StructureResult {
        try await storage.run(StructureReportTransaction(.init(axis: axis)))
    }

    public static func neighbors(
        _ storage: GRDBStorage,
        id: String,
        k: Int,
        cliSessionId: String = ""
    ) async throws -> [Candidates.NeighborScore] {
        let outcome = try await storage.run(
            NeighborsTransaction(
                .init(
                    id: id,
                    k: k,
                    cliSessionId: cliSessionId
                )
            )
        )

        try await applyRecord(storage, outcome.record)

        return outcome.scores
    }

    public static func noteStats(
        _ storage: GRDBStorage,
        id: String
    ) async throws -> NoteStats? {
        try await storage.read { scope in try scope.run(NoteStatsTransaction(id: id)) }
    }

    public static func axisStats(
        _ storage: GRDBStorage,
        axis: String
    ) async throws -> AxisStats {
        try await storage.read { scope in try scope.run(AxisStatsTransaction(axis: axis)) }
    }

    public static func overallStats(_ storage: GRDBStorage) async throws -> OverallStats {
        try await storage.read { scope in try scope.run(OverallStatsTransaction()) }
    }

    public static func list(
        _ storage: GRDBStorage,
        priority: String?,
        axis: String?,
        stale: Bool,
        sourceStale: Bool,
        limit: Int?
    ) async throws -> [Reads.ListRow] {
        try await storage.run(
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

    public static func history(
        _ storage: GRDBStorage,
        noteId: String,
        limit: Int
    ) async throws -> [Reads.HistoryEvent] {
        try await storage.run(
            NoteHistoryTransaction(
                .init(
                    noteId: noteId,
                    limit: limit
                )
            )
        )
    }

    public static func lint(
        _ storage: GRDBStorage,
        id: String? = nil,
        code: String? = nil,
        severity: String? = nil,
        limit: Int? = nil,
        includeDismissed: Bool = false
    ) async throws -> [Lint.Issue] {
        try await storage.run(
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

    public static func enrichment(_ storage: GRDBStorage) async throws -> EnrichmentStatus {
        try await storage.read { scope in try scope.run(EnrichmentStatusTransaction()) }
    }

    public static func candidates(
        _ storage: GRDBStorage,
        kinds: [String],
        limit: Int
    ) async throws -> [String: Candidates.Batch] {
        try await storage.run(
            CandidatesTransaction(
                .init(
                    kinds: kinds,
                    limit: limit
                )
            )
        )
    }

    // MARK: - Private
    // The one place read-derived side effects get applied — surfaces never juggle
    // the record by hand. Throws when the mandatory state transition (activation)
    // fails; advisory failures come back as degraded notes.
    @discardableResult
    private static func applyRecord(
        _ storage: GRDBStorage,
        _ record: RecordRetrievalTransaction.Parameter?
    ) async throws -> [String] {
        guard let record else { return [] }

        return try await storage.run(RecordRetrievalTransaction(record))
    }
}
