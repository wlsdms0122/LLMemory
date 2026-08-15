//
//  RetrievalServiceable.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation

// The associative read surface — search, related, neighbors, entity.
//
// Features only: every member opens and closes its own unit of work. Work
// a collaborator needs *inside* a scope it already holds is not a feature
// of this service — it is a transaction, and it lives in the DB module
// where scopes are spoken (BuildFramingSnapshotTransaction).
//
// applyRecord is the exception that proves it: it takes a record, not a
// scope, and opens its own write.
protocol RetrievalServiceable: Sendable {
    func search(
        query: String,
        tags: [String],
        limit: Int,
        expand: Int,
        sessionId: String?,
        includeStale: Bool,
        excludeTags: [String],
        raw: Bool
    ) async throws -> (rows: [SearchRow], extra: [ExpandedNote])

    func related(
        text: String,
        kind: String?,
        sessionId: String?,
        includeBodies: Bool
    ) async throws -> RelatedResult

    func neighbors(
        id: String,
        k: Int,
        sessionId: String?
    ) async throws -> [NeighborScore]

    func entity(
        name: String?,
        limit: Int
    ) async throws -> [EntityHit]

    @discardableResult
    func applyRecord(_ record: RetrievalRecord?) async throws -> [String]
}
