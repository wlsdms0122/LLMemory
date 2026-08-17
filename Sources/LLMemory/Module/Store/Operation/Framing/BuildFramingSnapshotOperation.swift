//
//  BuildFramingSnapshotOperation.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

// The associative snapshot for a piece of text — similar notes, their tag
// neighbourhood, link and vector expansions, entity hits — assembled from
// one consistent read.
//
// It is an operation because that is all it ever was: seven fetches whose
// answers must come from the same snapshot, with the text read for cues in
// front. Expansions degrade rather than fail, so a missing vector index costs
// the caller its extra hits and nothing else.
//
// How the text is read and how wide the fetches reach are both the caller's,
// and both arrive as parameters. The shadow replay — which re-runs a query
// under one swapped gene value — is the caller that makes this matter: it now
// says which numbers it replayed with instead of handing down a brain that
// answers differently than the one the baseline used.
struct BuildFramingSnapshotOperation: GRDBReadOperation {
    // MARK: - Property
    let text: String
    let linkKind: LinkKind?
    let sessionId: SessionId?
    let keywords: any KeywordExtracting
    let entities: any EntityHinting
    let similarLimit: Int
    let expandHops: Int
    let neighborFloor: Double
    let siblingDiscount: Double
    let primingWindowMin: Int
    let primingAlpha: Double

    // MARK: - Initializer
    init(
        text: String,
        linkKind: LinkKind? = nil,
        sessionId: SessionId? = nil,
        keywords: any KeywordExtracting,
        entities: any EntityHinting,
        similarLimit: Int,
        expandHops: Int,
        neighborFloor: Double,
        siblingDiscount: Double,
        primingWindowMin: Int,
        primingAlpha: Double
    ) {
        self.text = text
        self.linkKind = linkKind
        self.sessionId = sessionId
        self.keywords = keywords
        self.entities = entities
        self.similarLimit = similarLimit
        self.expandHops = expandHops
        self.neighborFloor = neighborFloor
        self.siblingDiscount = siblingDiscount
        self.primingWindowMin = primingWindowMin
        self.primingAlpha = primingAlpha
    }

    // MARK: - Public
    func execute(_ db: Database) throws -> FramingSnapshot {
        let cues = keywords.keywords(in: text, limit: RetrievalCue.limit)
        let entityHints = entities.hints(in: text)
        let similarNotes = try FetchSimilarNotesOperation(
            keywords: cues,
            limit: similarLimit,
            sessionId: sessionId,
            primingWindowMin: primingWindowMin,
            primingAlpha: primingAlpha
        )
            .execute(db)
        let similarTagSet = Set(similarNotes.flatMap { note in note.tags })
        let topTagCounts = try FetchTopTagsOperation().execute(db)
        let cooccurrences = try FetchTagCooccurrenceOperation(tags: similarTagSet.sorted())
            .execute(db)
        let vocabEntries = try FetchTagVocabOperation().execute(db)
        let entityHits = try FetchEntityHitsOperation(entities: entityHints).execute(db)

        var degraded: [String] = []
        var linked: [ExpandedNote] = []

        if !similarNotes.isEmpty {
            do {
                linked = try ExpandLinksOperation(
                    noteIds: similarNotes.map { note in note.id },
                    hops: expandHops,
                    kind: linkKind,
                    minWeight: neighborFloor,
                    siblingDiscount: siblingDiscount
                )
                    .execute(db)
            } catch {
                degraded.append("linked: \(error)")
            }
        }

        var vectorLinked: [VectorHit] = []

        if !similarNotes.isEmpty {
            let already = Set(similarNotes.map { note in note.id })
                .union(linked.map { note in note.id })

            do {
                vectorLinked = try ExpandByVectorsOperation(
                    seedIds: similarNotes.map { note in note.id },
                    limit: similarLimit,
                    excludeIds: already
                )
                    .execute(db)
            } catch {
                degraded.append("vector_linked: \(error)")
            }
        }

        return FramingSnapshot(
            keywords: cues,
            similar: similarNotes,
            linked: linked,
            vectorLinked: vectorLinked,
            topTags: topTagCounts,
            cooccur: cooccurrences,
            vocab: vocabEntries,
            entityHints: entityHints,
            entityHits: entityHits,
            degraded: degraded
        )
    }

    // MARK: - Private
}
