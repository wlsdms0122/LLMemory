//
//  NotesServiceable.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation

// Reading notes — bodies, section slices, budgeted cuts, and the catalog
// listings that answer "which notes" without opening any of them.
//
// Each async member is a thin `storage.read { … }` around the scope-taking
// core below it, and both are on the contract: a caller already inside a
// scope composes with the core, and it is also where the retrieval record
// surfaces so its applier can decide what to do with it.
protocol NotesServiceable: Sendable {
    func get(
        ids: [String],
        cliSessionId: String
    ) async throws -> (found: [NoteView], missing: [String])

    func getSections(
        id: String,
        sections: [String],
        cliSessionId: String
    ) async throws -> (note: NoteView, slices: [SectionSlice])

    func getBudget(
        id: String,
        budget: Int,
        cliSessionId: String
    ) async throws -> (note: NoteView, cut: BudgetCut)

    func toc(
        id: String,
        cliSessionId: String
    ) async throws -> (note: NoteView, entries: [TocEntry])

    func template(
        id: String,
        cliSessionId: String
    ) async throws -> (note: NoteView, frame: [TemplateFrameNode])

    func list(
        priority: String?,
        tags: [String],
        fields: [NoteFieldFilter],
        stale: Bool,
        sourceStale: Bool,
        limit: Int?
    ) async throws -> [NoteListRow]

    func history(
        noteId: String,
        limit: Int
    ) async throws -> [NoteHistoryEvent]

    func tree(prefix: String?) async throws -> [TreeRow]

    func structure(prefix: String?) async throws -> StructureResult

    func get(
        _ scope: GRDBReadScope,
        ids: [String],
        sessionId: String?
    ) throws -> (found: [NoteView], missing: [String], record: RetrievalRecord?)

    func getSections(
        _ scope: GRDBReadScope,
        id: String,
        sections: [String],
        sessionId: String?
    ) throws -> (note: NoteView, slices: [SectionSlice], record: RetrievalRecord?)

    func getBudget(
        _ scope: GRDBReadScope,
        id: String,
        budget: Int,
        sessionId: String?
    ) throws -> (note: NoteView, record: RetrievalRecord?, cut: BudgetCut)

    func toc(
        _ scope: GRDBReadScope,
        id: String,
        sessionId: String?
    ) throws -> (note: NoteView, entries: [TocEntry], record: RetrievalRecord?)

    func template(
        _ scope: GRDBReadScope,
        id: String,
        sessionId: String?
    ) throws -> (note: NoteView, frame: [TemplateFrameNode], record: RetrievalRecord?)

    func structure(_ scope: GRDBReadScope, prefix: String?) throws -> StructureResult
}
