//
//  RecordCatalogTests.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/9/26.
//

import Testing
import Foundation
import GRDB
@testable import LLMemory

// The record catalog mirrors the v1 schema by hand — nothing ties a record's
// table/column names to the DDL at compile time. A full insert→fetch round trip
// against a migrated database is that tie: an unknown column fails the insert,
// a missing/misnamed column fails the decode.
@Suite("RecordCatalog Tests")
struct RecordCatalogTests {
    // MARK: - Property
    private let queue: DatabaseQueue

    // MARK: - Initializer
    init() throws {
        let queue = try DatabaseQueue()

        try queue.write { db in
            try Migration1().migrate(db)
        }

        self.queue = queue
    }

    // MARK: - Test
    @Test("every table record round-trips through a migrated schema")
    func recordsRoundTrip() throws {
        try queue.write { db in
            // Parents first — children hold foreign keys into them.
            try AxisRecord(axis: "tech", createdAt: 1).insert(db)
            try TagVocabRecord(tag: "swift", createdAt: 1).insert(db)
            try TagAliasRecord(alias: "스위프트", canonical: "swift", createdAt: 1).insert(db)
            try NoteRecord(
                id: "note-a",
                axis: "tech",
                path: "cortex/tech/note-a.md",
                title: "Note A",
                summary: "summary",
                priority: "lazy",
                editedAt: 3,
                stale: false,
                template: nil,
                locked: false,
                wordCount: 10,
                sectionCount: 2,
                contentHash: "hash"
            ).insert(db)
            try NoteRecord(
                id: "note-b",
                axis: "tech",
                path: "cortex/tech/note-b.md",
                title: "Note B",
                summary: nil,
                priority: "eager",
                editedAt: 3,
                stale: true,
                template: nil,
                locked: true,
                wordCount: 5,
                sectionCount: 1,
                contentHash: "hash-b"
            ).insert(db)

            try NoteUsageRecord(noteId: "note-a", hitCount: 3, lastRetrievedAt: 9, createdAt: 1).insert(db)
            try NoteSourceRecord(
                noteId: "note-a",
                sourceHash: "sh",
                sourceStale: true,
                declHash: "dh"
            ).insert(db)
            try TagRecord(noteId: "note-a", tag: "swift").insert(db)
            try NoteExtraRecord(noteId: "note-a", key: "affect", value: "high").insert(db)
            try NoteLinkRecord(
                src: "note-a",
                dst: "note-b",
                kind: "assoc",
                weight: 0.4,
                createdAt: 1,
                lastActivatedAt: 2,
                provenance: "forge:capture"
            ).insert(db)
            try NoteRetrievalTermRecord(
                noteId: "note-a",
                kind: "alias",
                term: "노트",
                status: "pending",
                provenance: nil,
                rejectReason: nil,
                createdAt: 1,
                validatedAt: nil
            ).insert(db)
            try NoteRefMarkerRecord(src: "note-a", marker: "note-b", createdAt: 1).insert(db)
            try NoteVectorRecord(noteId: "note-a", dim: 2, vec: Data([0, 0, 128, 63]), builtAt: 1).insert(db)
            try MetaRecord(key: "vectors.dim", value: "2").insert(db)
            try RippleFlagRecord(
                noteId: "note-a",
                flag: "split-candidate",
                reason: "big",
                createdAt: 1,
                lastFlaggedAt: 2,
                flagCount: 1,
                resolvedAt: nil
            ).insert(db)
            try EntityIndexRecord(entity: "GRDB", noteId: "note-a", lastSeenAt: 1, hitCount: 2).insert(db)
            try CandidateDismissalRecord(
                noteId: "note-a",
                kind: "lint:note-oversized",
                dismissCount: 1,
                wordCount: 10,
                sectionCount: 2,
                generation: 0,
                reason: "keep",
                lastDismissedAt: 1
            ).insert(db)
            try CorpusDismissalRecord(
                targetKey: "tag-pair:금리|금융",
                kind: "tag-merge",
                dismissCount: 1,
                generation: 0,
                reason: "distinct",
                lastDismissedAt: 1
            ).insert(db)
            try GenomeRecord(geneId: "links.decay", value: 0.5, updatedAt: 1).insert(db)

            var lifecycle = NoteLifecycleEventRecord(noteId: "note-a", kind: "created", reason: nil, createdAt: 1)
            try lifecycle.insert(db)
            #expect(lifecycle.id != nil)

            var window = ActivityWindowRecord(startedAt: 1, endedAt: 2, label: "session", queryCount: 3)
            try window.insert(db)

            let windowId = try #require(window.id)

            var hit = RetrievalHitRecord(
                windowId: windowId,
                noteId: "note-a",
                surfacedAt: 1,
                cmd: "search",
                surfaceKind: "hit",
                usedSignal: nil,
                usedAt: nil
            )
            try hit.insert(db)
            #expect(hit.id != nil)

            var genomeEvent = GenomeEventRecord(
                geneId: "links.decay",
                oldValue: nil,
                newValue: 0.5,
                cause: "set_gene",
                detail: nil,
                ts: 1
            )
            try genomeEvent.insert(db)
            #expect(genomeEvent.id != nil)

            var event = EventRecord(ts: 1, kind: "capture", sessionId: "s", payload: "{}")
            try event.insert(db)
            #expect(event.id != nil)
        }

        try queue.read { db in
            #expect(try AxisRecord.fetchCount(db) == 1)
            #expect(try TagVocabRecord.fetchAll(db).count == 1)
            #expect(try TagAliasRecord.fetchAll(db).first?.canonical == "swift")

            let notes = try NoteRecord.fetchAll(db).sorted { lhs, rhs in lhs.id < rhs.id }
            #expect(notes.count == 2)
            #expect(notes.first?.stale == false)
            #expect(notes.last?.locked == true)

            #expect(try NoteUsageRecord.fetchOne(db)?.hitCount == 3)
            #expect(try NoteSourceRecord.fetchOne(db)?.sourceStale == true)
            #expect(try TagRecord.fetchAll(db).count == 1)
            #expect(try NoteLinkRecord.fetchOne(db)?.weight == 0.4)
            #expect(try NoteRetrievalTermRecord.fetchOne(db)?.status == "pending")
            #expect(try NoteRefMarkerRecord.fetchOne(db)?.marker == "note-b")
            #expect(try NoteVectorRecord.fetchOne(db)?.dim == 2)
            #expect(try MetaRecord.fetchOne(db)?.value == "2")
            #expect(try RippleFlagRecord.fetchOne(db)?.resolvedAt == nil)
            #expect(try EntityIndexRecord.fetchOne(db)?.hitCount == 2)
            #expect(try CandidateDismissalRecord.fetchOne(db)?.generation == 0)
            #expect(try CorpusDismissalRecord.fetchOne(db)?.targetKey == "tag-pair:금리|금융")
            #expect(try GenomeRecord.fetchOne(db)?.value == 0.5)
            #expect(try NoteLifecycleEventRecord.fetchOne(db)?.kind == "created")
            #expect(try ActivityWindowRecord.fetchOne(db)?.label == "session")
            #expect(try RetrievalHitRecord.fetchOne(db)?.surfaceKind == "hit")
            #expect(try GenomeEventRecord.fetchOne(db)?.cause == "set_gene")
        }
    }
}
