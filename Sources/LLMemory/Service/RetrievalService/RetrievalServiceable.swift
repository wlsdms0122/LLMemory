//
//  RetrievalServiceable.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation

// The associative read surface — search, related, neighbors, entity.
//
// The scope-taking members are here because siblings compose with them inside
// a scope somebody else opened: notes records a retrieval it caused, genome
// replays a logged query under a candidate gene value. They are part of the
// contract precisely because a collaborator depends on them, and a contract
// that hides what its collaborators call is not the contract.
protocol RetrievalServiceable: Sendable {
    func search(
        query: String,
        tags: [String],
        limit: Int,
        expand: Int,
        cliSessionId: String,
        includeStale: Bool,
        excludeTags: [String],
        raw: Bool
    ) async throws -> (rows: [SearchRow], extra: [ExpandedNote])

    func related(
        text: String,
        kind: String?,
        cliSessionId: String,
        includeBodies: Bool
    ) async throws -> RelatedResult

    func neighbors(
        id: String,
        k: Int,
        cliSessionId: String
    ) async throws -> [NeighborScore]

    func entity(
        name: String?,
        limit: Int
    ) async throws -> [EntityHit]

    func search(
        _ scope: GRDBReadScope,
        query: String,
        tags: [String],
        limit: Int,
        expand: Int,
        sessionId: String?,
        includeStale: Bool,
        excludeTags: [String]?,
        sinceTs: Int?,
        raw: Bool
    ) throws -> (rows: [SearchRow], extra: [ExpandedNote], record: RetrievalRecord)

    func related(
        _ scope: GRDBReadScope,
        text: String,
        kind: String?,
        sessionId: String?,
        includeBodies: Bool
    ) throws -> (result: RelatedResult, record: RetrievalRecord)

    func neighbors(
        _ scope: GRDBReadScope,
        id: String,
        k: Int,
        sessionId: String?
    ) throws -> (scores: [NeighborScore], record: RetrievalRecord?)

    func snapshot(
        _ scope: GRDBReadScope,
        userInput: String,
        agentOutput: String,
        similarLimit: Int?,
        expandHops: Int?,
        linkKind: String?,
        sessionId: String?
    ) throws -> FramingSnapshot

    @discardableResult
    func applyRecord(_ record: RetrievalRecord?) async throws -> [String]
}
