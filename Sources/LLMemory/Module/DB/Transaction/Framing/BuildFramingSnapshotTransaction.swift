//
//  BuildFramingSnapshotTransaction.swift
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
// It is a transaction because that is all it ever was: seven fetches whose
// answers must come from the same snapshot, with keyword extraction in
// front — extraction is part of assembling the snapshot, not something a
// caller hands in. Expansions degrade rather than fail, so a missing vector
// index costs the caller its extra hits and nothing else.
//
// The limits are read from the gene catalog here and nowhere else. A
// parameter beside them would give "which limit did this replay use?" two
// answers, and the shadow replay (which swaps a gene value and re-runs) is
// exactly the caller that would make the two disagree.
struct BuildFramingSnapshotTransaction: GRDBReadTransaction {
    // MARK: - Property
    let text: String
    let linkKind: String?
    let sessionId: String?

    // MARK: - Initializer
    init(text: String, linkKind: String? = nil, sessionId: String? = nil) {
        self.text = text
        self.linkKind = linkKind
        self.sessionId = sessionId
    }

    // MARK: - Public
    func perform(_ db: Database) throws -> FramingSnapshot {
        let similarLimit = Genes.int("related.similar_limit")
        let expandHops = Genes.int("related.expand_hops")
        let keywords = FrequencyKeywords.extractKeywords(text)
        let entityHints = PatternEntityHints.extractEntityHints(text)
        let similarNotes = try FetchSimilarNotesTransaction(
            keywords: keywords,
            limit: similarLimit,
            sessionId: sessionId
        )
            .perform(db)
        let similarTagSet = Set(similarNotes.flatMap { note in note.tags })
        let topTagCounts = try FetchTopTagsTransaction().perform(db)
        let cooccurrences = try FetchTagCooccurrenceTransaction(tags: similarTagSet.sorted())
            .perform(db)
        let vocabEntries = try FetchTagVocabTransaction().perform(db)
        let entityHits = try FetchEntityHitsTransaction(entities: entityHints).perform(db)

        var degraded: [String] = []
        var linked: [ExpandedNote] = []

        if !similarNotes.isEmpty {
            do {
                linked = try ExpandLinksTransaction(
                    noteIds: similarNotes.map { note in note.id },
                    hops: expandHops,
                    kind: linkKind
                )
                    .perform(db)
            } catch {
                degraded.append("linked: \(error)")
            }
        }

        var vectorLinked: [VectorHit] = []

        if !similarNotes.isEmpty {
            let already = Set(similarNotes.map { note in note.id })
                .union(linked.map { note in note.id })

            do {
                vectorLinked = try ExpandByVectorsTransaction(
                    seedIds: similarNotes.map { note in note.id },
                    limit: similarLimit,
                    excludeIds: already
                )
                    .perform(db)
            } catch {
                degraded.append("vector_linked: \(error)")
            }
        }

        return FramingSnapshot(
            keywords: keywords,
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
