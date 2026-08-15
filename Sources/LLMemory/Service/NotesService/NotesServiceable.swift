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
// Every member opens its own scope. The sync cores underneath are not here:
// no collaborator composes with them, and a contract that lists them would
// be handing out the inside of the implementation to nobody's benefit.
protocol NotesServiceable: Sendable {
    func get(
        ids: [String],
        sessionId: SessionId?
    ) async throws -> (found: [NoteView], missing: [String])

    func getSections(
        id: String,
        sections: [String],
        sessionId: SessionId?
    ) async throws -> (note: NoteView, slices: [SectionSlice])

    func getBudget(
        id: String,
        budget: Int,
        sessionId: SessionId?
    ) async throws -> (note: NoteView, cut: BudgetCut)

    func toc(
        id: String,
        sessionId: SessionId?
    ) async throws -> (note: NoteView, entries: [TocEntry])

    func template(
        id: String,
        sessionId: SessionId?
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
}
