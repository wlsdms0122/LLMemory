//
//  RetrievalServiceable.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation

// The associative read surface — search, related, neighbors, entity.
//
// Two scope-taking members are here, and only two, because exactly two
// collaborators call them: genome replays a logged query under a candidate
// gene value (`snapshot`), and notes applies the retrieval its own reads
// caused (`applyRecord`). The rest of the sync cores stay off the contract —
// what a contract admits is what a collaborator asks for, and everything
// beyond that is an implementation detail handed out for free.
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
