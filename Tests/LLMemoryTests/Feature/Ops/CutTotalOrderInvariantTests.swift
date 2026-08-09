//
//  CutTotalOrderInvariantTests.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import GRDB
import Testing
@testable import LLMemory

// Every read surface that cuts its result set has to order on something unique. These rows are built
// so the primary sort key ties on purpose: whatever survives the cut then shows whether the tiebreak
// is real or whether the answer is whichever row SQLite reached first.
@Suite("CutTotalOrderInvariant Tests", .serialized)
struct CutTotalOrderInvariantTests {
    // MARK: - Property
    private let home: MemoryHome
    
    // MARK: - Initializer
    init() throws {
        home = try MemoryHome()
    }
    
    // MARK: - Test
    @Test("entity hits cut deterministically when every row shares a last-seen time")
    func entityHitsCutIsDeterministicOnLastSeenTies() throws {
        // Given
        let ids = (1 ... 6).map { index in "ent-n\(index)" }
        
        try seedNotes(ids: ids)
        try seedEntityIndex(ids: ids)
        
        // When
        let hits = try home.read { database in
            try FetchEntityHitsTransaction(entities: ["acme"], limitPerEntity: 3).perform(database)
        }
        
        // Then
        #expect(hits.map(\.noteId) == ["ent-n1", "ent-n2", "ent-n3"])
    }
    
    @Test("entity lookup cuts deterministically, named or not")
    func entityLookupCutIsDeterministicOnLastSeenTies() throws {
        // Given
        let ids = (1 ... 6).map { index in "lk-n\(index)" }
        
        try seedNotes(ids: ids)
        try seedEntityIndex(ids: ids)
        
        // When
        let named = try home.read { database in try Reads.entityLookup(database, name: "acme", limit: 3) }
        let all = try home.read { database in try Reads.entityLookup(database, name: nil, limit: 3) }
        
        // Then
        #expect(named.map(\.noteId) == ["lk-n1", "lk-n2", "lk-n3"])
        #expect(all.map(\.noteId) == ["lk-n1", "lk-n2", "lk-n3"])
    }
    
    @Test("reconsolidate candidates cut deterministically when every flag shares a creation time")
    func flaggedCutIsDeterministicOnCreatedAtTies() throws {
        // Given
        let ids = (1 ... 6).map { index in "fl-n\(index)" }
        
        try seedNotes(ids: ids)
        try home.database().write { database in
            for noteId in ids.sorted(by: >) {
                try database.execute(sql: """
                    INSERT INTO ripple_flags (note_id, flag, reason, created_at, last_flagged_at)
                    VALUES (?, 'reconsolidate', 'r', ?, ?)
                    """, arguments: [noteId, home.now, home.now])
            }
        }
        
        // When
        let rows = try home.read { database in try Candidates.reconsolidateCandidates(database, limit: 3) }
        
        // Then
        #expect(rows.map(\.id) == ["fl-n1", "fl-n2", "fl-n3"])
    }
    
    @Test("split candidates cut deterministically when every note is the same size")
    func splitCandidatesCutIsDeterministicOnSizeTies() throws {
        // Given
        let ids = (1 ... 6).map { index in "sp-n\(index)" }
        
        try seedNotes(ids: ids, wordCount: 500, sectionCount: 5)
        try seedTags(ids: ids) { _ in ["ta", "tb", "tc"] }
        
        // When
        let rows = try home.read { database in try Candidates.splitCandidates(database, limit: 3) }
        
        // Then
        #expect(rows.map(\.id) == ["sp-n1", "sp-n2", "sp-n3"])
    }
    
    @Test("initial link seeding cuts deterministically when every sibling shares the same tag")
    func seedInitialLinksCutIsDeterministicOnSharedTies() throws {
        // Given
        let siblings = (1 ... 7).map { index in "sd-n\(index)" }
        
        try seedNotes(ids: siblings + ["sd-new"])
        try seedTags(ids: siblings + ["sd-new"]) { _ in ["shared"] }
        
        // When
        try home.database().write { database in
            try Handlers.seedInitialLinks(database, nid: "sd-new", tags: ["shared"])
        }
        
        // Then
        let linked = try home.read { database in
            try String.fetchAll(database, sql: """
                SELECT CASE WHEN src = 'sd-new' THEN dst ELSE src END
                FROM note_links WHERE src = 'sd-new' OR dst = 'sd-new'
                ORDER BY 1
                """)
        }
        
        #expect(linked == ["sd-n1", "sd-n2", "sd-n3", "sd-n4", "sd-n5"])
    }
    
    @Test("tag co-occurrence cuts deterministically when every pair has the same count")
    func cooccurCutIsDeterministicOnCountTies() throws {
        // Given
        let ids = (1 ... 6).map { index in "co-n\(index)" }
        
        try seedNotes(ids: ids)
        try seedTags(ids: ids) { offset in ["hub", "x\(offset + 1)"] }
        
        // When
        let pairs = try home.read { database in try Vocab.cooccurFor(database, tags: ["hub"], limit: 3) }
        
        // Then
        #expect(pairs.map { pair in "\(pair.tagA)|\(pair.tagB)" } == ["hub|x1", "hub|x2", "hub|x3"])
        #expect(pairs.allSatisfy { pair in pair.count == 1 })
    }
    
    @Test("cluster members come back ordered by id, so the same component reads the same way twice")
    func clusterMembersAreOrderedById() throws {
        // Given
        let ids = ["cl-a", "cl-b", "cl-c"]
        
        try seedNotes(ids: ids)
        try home.database().write { database in
            for (source, destination) in [("cl-a", "cl-b"), ("cl-b", "cl-c")] {
                try database.execute(sql: """
                    INSERT INTO note_links (src, dst, kind, weight, created_at, last_activated_at)
                    VALUES (?, ?, 'cooccur', 1.0, ?, ?)
                    """, arguments: [source, destination, home.now, home.now])
            }
        }
        
        // When
        let clusters = try home.read { database in try Candidates.clusters(database) }
        
        // Then
        #expect(clusters.count == 1)
        #expect(clusters.first?.members.map(\.id) == ["cl-a", "cl-b", "cl-c"])
    }
    
    @Test("search cuts deterministically when every row scores the same")
    func searchAggregationCutIsDeterministicOnRankTies() throws {
        // Given
        let ids = (1 ... 6).map { index in "se-n\(index)" }
        
        try seedNotes(ids: ids)
        try home.database().write { database in
            for noteId in ids.sorted(by: >) {
                try database.execute(sql: """
                    INSERT INTO notes_fts (id, section, title, summary, body, enrich)
                    VALUES (?, '', 'same title', '', 'zebra corpus body', '')
                    """, arguments: [noteId])
            }
        }
        
        // When
        let rows = try home.read { database in try Search.fts(database, query: "zebra", limit: 3) }
        
        // Then
        #expect(rows.map(\.id) == ["se-n1", "se-n2", "se-n3"])
    }
    
    // MARK: - Private
    // Inserted in reverse id order so physical row order disagrees with the expected answer — a cut
    // that leans on insertion order fails here instead of passing by luck.
    private func seedNotes(ids: [String], wordCount: Int = 0, sectionCount: Int = 0) throws {
        try home.database().write { database in
            try database.execute(
                sql: "INSERT OR IGNORE INTO axes (axis, description, created_at) VALUES ('flow','flow',?)",
                arguments: [home.now]
            )
            
            for noteId in ids.sorted(by: >) {
                try database.execute(sql: """
                    INSERT INTO notes (id, axis, path, title, summary, priority, file_mtime, indexed_at,
                                       word_count, section_count)
                    VALUES (?, 'flow', ?, ?, '', 'lazy', ?, ?, ?, ?)
                    """, arguments: [
                        noteId, "tmp/\(noteId).md", noteId, home.now, home.now, wordCount, sectionCount
                    ])
                
                let file = home.url.appendingPathComponent("tmp/\(noteId).md")
                
                try FileManager.default.createDirectory(
                    at: file.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try (Frontmatter.dump(FrontmatterDoc(id: noteId, title: noteId, axis: "flow"))
                    + "## A\nx\n## B\ny\n").write(to: file, atomically: true, encoding: .utf8)
            }
        }
    }
    
    private func seedTags(ids: [String], tags: (Int) -> [String]) throws {
        try home.database().write { database in
            var vocabulary = Set<String>()
            
            for (offset, noteId) in ids.enumerated().reversed() {
                for tag in tags(offset) {
                    if vocabulary.insert(tag).inserted {
                        try database.execute(
                            sql: "INSERT OR IGNORE INTO tag_vocab (tag, created_at) VALUES (?, ?)",
                            arguments: [tag, home.now]
                        )
                    }
                    
                    try database.execute(
                        sql: "INSERT INTO tags (note_id, tag) VALUES (?, ?)",
                        arguments: [noteId, tag]
                    )
                }
            }
        }
    }
    
    private func seedEntityIndex(ids: [String]) throws {
        try home.database().write { database in
            for noteId in ids.sorted(by: >) {
                try database.execute(sql: """
                    INSERT INTO entity_index (entity, note_id, last_seen_at, hit_count)
                    VALUES ('acme', ?, ?, 1)
                    """, arguments: [noteId, home.now])
            }
        }
    }
}
