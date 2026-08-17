//
//  EnrichmentTests.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/8/26.
//

import Testing
import Foundation
import GRDB
@testable import LLMemory

@Suite("Enrichment Tests", .serialized)
struct EnrichmentTests {
    // MARK: - Property
    private let home: MemoryHome
    
    private let indexer = Indexer()

    // MARK: - Initializer
    init() throws {
        home = try MemoryHome()
    }
    
    // MARK: - Test
    
    // add_retrieval_terms — validate
    @Test("a retrieval term declares a kind, and an unknown one is refused")
    func addRetrievalTermsValidatesKind() throws {
        // Given
        home.createNote(id: "enr-n1", content: "## A\nalpha bravo charlie keyword\n")
        
        // When
        let result = home.apply([[
            "op": "add_retrieval_terms", "id": "enr-n1",
            "kind": "bogus", "terms": ["x"]
        ]])
        
        // Then
        #expect(result.status != "ok")
    }
    
    @Test("an empty term list is refused rather than recorded as a no-op")
    func addRetrievalTermsRejectsEmptyTerms() throws {
        // Given
        home.createNote(id: "enr-n2")
        
        // When
        let result = home.apply([[
            "op": "add_retrieval_terms", "id": "enr-n2",
            "kind": "alias", "terms": []
        ]])
        
        // Then
        #expect(result.status != "ok")
    }
    
    @Test("more terms than the cap allows is refused whole")
    func addRetrievalTermsRejectsOverCap() throws {
        // Given
        home.createNote(id: "enr-n3")
        
        // When
        let many = (0..<99).map { index in "term\(index)" }
        let result = home.apply([[
            "op": "add_retrieval_terms", "id": "enr-n3",
            "kind": "alias", "terms": many
        ]])
        
        // Then
        #expect(result.status != "ok")
        #expect(result.error.lowercased().contains("too many"))
    }
    
    @Test("terms for a note that does not exist are refused")
    func addRetrievalTermsRejectsUnknownNote() throws {
        // When
        let result = home.apply([[
            "op": "add_retrieval_terms", "id": "nope-xyz",
            "kind": "alias", "terms": ["x"]
        ]])
        
        // Then
        #expect(result.status != "ok")
    }
    
    // add_retrieval_terms — write + round-trip activation
    @Test("an alias the body supports becomes active")
    func aliasMatchingBodyRoundTripsToActive() throws {
        // Given
        home.createNote(id: "enr-rt1",
            content: "## Body\nzephyrine quasar specific distinctive content here\n")
        
        // When
        let result = home.apply([[
            "op": "add_retrieval_terms", "id": "enr-rt1",
            "kind": "alias", "terms": ["zephyrine quasar"],
            "provenance": "test:capture"
        ]])
        
        // Then
        #expect(result.status == "ok")
        
        let queue = try home.storage.connect()
        let status = try queue.read { db in
            try String.fetchOne(db, sql: """
                SELECT status FROM note_retrieval_terms
                WHERE note_id = 'enr-rt1' AND kind = 'alias'
                """)
        }
        
        #expect(status == "active")
        
        let hit = try queue.read { db in
            try String.fetchAll(db, sql: "SELECT id FROM notes_fts WHERE notes_fts MATCH ?",
                arguments: ["\"zephyrine\""])
        }
        
        #expect(hit.contains("enr-rt1"))
    }
    
    @Test("proposing a rejected term again reopens it for review")
    func reproposalReopensRejectedTerm() throws {
        // When
        home.createNote(id: "enr-ro1", content: "## Body\nplain body without the token\n")
        
        // Then
        #expect(home.apply([[
            "op": "add_retrieval_terms", "id": "enr-ro1",
            "kind": "alias", "terms": ["xylophonic gradient"], "provenance": "gen1"
        ]]).status == "ok")
        
        let queue = try home.storage.connect()
        
        try home.storage.writeLock {
            try queue.write { db in
                try db.execute(sql: """
                    UPDATE note_retrieval_terms
                    SET status='rejected', reject_reason='round-trip-stale', validated_at=1
                    WHERE note_id='enr-ro1'
                    """)
            }
        }
        
        #expect(home.apply([[
            "op": "patch_section", "id": "enr-ro1", "section": "## Body",
            "action": "append", "content": "xylophonic gradient now appears here\n"
        ]]).status == "ok")
        #expect(home.apply([[
            "op": "add_retrieval_terms", "id": "enr-ro1",
            "kind": "alias", "terms": ["xylophonic gradient"], "provenance": "gen2"
        ]]).status == "ok")
        
        let row = try queue.read { db in
            try Row.fetchOne(db, sql: """
                SELECT status, provenance, reject_reason FROM note_retrieval_terms
                WHERE note_id='enr-ro1' AND term='xylophonic gradient'
                """)
        }
        
        #expect(row?["status"] == "active", "a reproposal must pass revalidation — got \(String(describing: row))")
        #expect(row?["provenance"] == "gen2", "a reopened row belongs to whoever proposed it again")
        #expect((row?["reject_reason"] as String?) == nil, "the verdict fields must clear when the row reopens")
        #expect(home.apply([[
            "op": "add_retrieval_terms", "id": "enr-ro1",
            "kind": "alias", "terms": ["xylophonic gradient"], "provenance": "gen3"
        ]]).status == "ok")
        
        let after = try queue.read { db in
            try Row.fetchOne(db, sql: """
                SELECT status, provenance FROM note_retrieval_terms
                WHERE note_id='enr-ro1' AND term='xylophonic gradient'
                """)
        }
        
        #expect(after?["status"] == "active", "an already-active term is unchanged by a reproposal")
        #expect(after?["provenance"] == "gen2", "the provenance of the decision that validated it is preserved")
    }
    
    @Test("a rebuild preserves active retrieval terms — markdown cannot restate them")
    func rebuildPreservesActiveRetrievalTerms() throws {
        // When
        home.createNote(id: "enr-rb1",
            content: "## Body\nzephyrine quasar specific distinctive content here\n")
        
        // Then
        #expect(home.apply([[
            "op": "add_retrieval_terms", "id": "enr-rb1",
            "kind": "alias", "terms": ["zephyrine quasar"],
            "provenance": "test:capture"
        ]]).status == "ok")
        
        _ = try indexer.buildLocked(home.database(), home.brain, rebuild: true)
        
        let queue = try home.storage.connect()
        let (status, hit) = try home.read { db -> (String?, Bool) in
            let status = try String.fetchOne(db, sql: """
                SELECT status FROM note_retrieval_terms
                WHERE note_id = 'enr-rb1' AND kind = 'alias'
                """)
            let hit = try String.fetchAll(db, sql: "SELECT id FROM notes_fts WHERE notes_fts MATCH ?",
                arguments: ["\"zephyrine\""]).contains("enr-rb1")
            
            return (status, hit)
        }
        
        #expect(status == "active")
        #expect(hit)
    }
    
    @Test("the surviving note of a merge keeps the earlier creation time")
    func mergeWinnerCarriesCreatedAt() throws {
        // Given
        home.createNote(id: "mts-into", content: "## Body\ntarget body\n")
        home.createNote(id: "mts-from", content: "## Body\nother body\n")
        
        let queue = try home.storage.connect()
        let now = home.now
        
        // When
        try home.storage.writeLock {
            try queue.write { db in
                try db.execute(sql: """
                    INSERT INTO note_retrieval_terms (note_id, kind, term, status, created_at, reject_reason, validated_at)
                    VALUES ('mts-into', 'alias', 'xylophone', 'rejected', ?, 'idf', ?)
                    """, arguments: [now - 86400 * 60, now - 86400 * 59])
                try db.execute(sql: """
                    INSERT INTO note_retrieval_terms (note_id, kind, term, status, created_at)
                    VALUES ('mts-from', 'alias', 'xylophone', 'pending', ?)
                    """, arguments: [now])
            }
        }
        
        // Then
        #expect(home.apply([[
            "op": "merge_notes", "into_id": "mts-into", "from_ids": ["mts-from"],
            "merged_content": "## Body\ntarget body\nother body\n",
            "summary": "merged", "tags": ["flow"]
        ]]).status == "ok")
        
        let row = try queue.read { db in
            try Row.fetchOne(db, sql: """
                SELECT status, created_at FROM note_retrieval_terms
                WHERE note_id='mts-into' AND term='xylophone'
                """)
        }
        
        #expect(row?["status"] == "pending", "the stronger status wins the reconciliation")
        #expect((row?["created_at"] as Int? ?? 0) >= now, "created_at comes from the winner, so the revalidation window is preserved")
    }
    
    @Test("a merge carries the absorbed note's retrieval terms across")
    func mergePreservesRetrievalTerms() throws {
        // When
        home.createNote(id: "mrg-into", content: "## Body\ntarget note body here\n")
        home.createNote(id: "mrg-from", content: "## Body\nzephyrine quasar specific distinctive content\n")
        
        // Then
        #expect(home.apply([[
            "op": "add_retrieval_terms", "id": "mrg-from",
            "kind": "alias", "terms": ["zephyrine quasar"], "provenance": "test:capture"
        ]]).status == "ok")
        
        let result = home.apply([[
            "op": "merge_notes", "into_id": "mrg-into", "from_ids": ["mrg-from"],
            "merged_content": "## Body\ntarget note body here\nzephyrine quasar specific distinctive content\n",
            "summary": "merged", "tags": ["flow"]
        ]])
        
        #expect(result.status == "ok")
        
        let queue = try home.storage.connect()
        let (onInto, fromGone, hit) = try queue.read { db -> (String?, Bool, Bool) in
            let status = try String.fetchOne(db, sql:
                "SELECT status FROM note_retrieval_terms WHERE note_id='mrg-into' AND kind='alias'")
            let fromGone = (try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM notes WHERE id='mrg-from'") ?? 0) == 0
            let hit = try String.fetchAll(db, sql: "SELECT id FROM notes_fts WHERE notes_fts MATCH ?",
                arguments: ["\"zephyrine\""]).contains("mrg-into")
            
            return (status, fromGone, hit)
        }
        
        #expect(onInto == "active")
        #expect(fromGone)
        #expect(hit)
    }
    
    @Test("splitting a note with aliases requires the caller to acknowledge where they go")
    func splitOfAliasedNoteRequiresDropAck() throws {
        // When
        home.createNote(id: "spl-src",
            content: "## A\nzephyrine quasar alpha content\n## B\nbravo distinct content\n")
        
        // Then
        #expect(home.apply([[
            "op": "add_retrieval_terms", "id": "spl-src",
            "kind": "alias", "terms": ["zephyrine quasar"], "provenance": "test:capture"
        ]]).status == "ok")
        
        let into: [[String: Any]] = [
            ["id": "spl-a", "title": "A", "tags": ["flow"], "summary": "s", "sections": ["## A"]],
            ["id": "spl-b", "title": "B", "tags": ["flow"], "summary": "s", "sections": ["## B"]]
        ]
        let conflict = home.apply([["op": "split_note", "from_id": "spl-src", "into": into]])
        
        #expect(conflict.status == "conflict")
        #expect(conflict.conflict?.unresolved.contains { item in
            item.type == "term" && item.term == "zephyrine quasar"
        } == true)
        
        let routing: [[String: Any]] = [["type": "term", "term": "zephyrine quasar", "to": ["spl-a"]]]
        
        #expect(home.apply([["op": "split_note", "from_id": "spl-src", "into": into, "routing": routing]]).status == "ok")
        
        let queue = try home.storage.connect()
        let (onChild, provenance) = try queue.read { db -> (Bool, String?) in
            let count = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM note_retrieval_terms WHERE note_id='spl-a' AND term='zephyrine quasar'") ?? 0
            let provenance = try String.fetchOne(db, sql: "SELECT provenance FROM note_retrieval_terms WHERE note_id='spl-a' AND term='zephyrine quasar'")
            
            return (count > 0, provenance)
        }
        
        #expect(onChild, "routed alias did not land on the chosen child")
        #expect(provenance == "test:capture", "routed alias lost its provenance")
    }
    
    // NoteArtifactPolicy generalization — not just alias, but all non-restorable authored artifacts
    @Test("renaming a note carries its authored artifacts to the new id")
    func migrateReparentsAuthoredArtifacts() throws {
        // When
        home.createNote(id: "mig-src", content: "## Body\nzephyrine quasar content\n")
        
        // Then
        #expect(home.apply([["op": "add_retrieval_terms", "id": "mig-src",
            "kind": "alias", "terms": ["zephyrine quasar"], "provenance": "t"]]).status == "ok")
        #expect(home.apply([["op": "migrate_note", "id": "mig-src", "new_id": "mig-dst"]]).status == "ok")
        
        let queue = try home.storage.connect()
        let (term, sourceGone, hit) = try queue.read { db -> (String?, Bool, Bool) in
            let term = try String.fetchOne(db, sql: "SELECT status FROM note_retrieval_terms WHERE note_id='mig-dst'")
            let sourceGone = (try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM notes WHERE id='mig-src'") ?? 0) == 0
            let hit = try String.fetchAll(db, sql: "SELECT id FROM notes_fts WHERE notes_fts MATCH ?",
                arguments: ["\"zephyrine\""]).contains("mig-dst")
            
            return (term, sourceGone, hit)
        }
        
        #expect(term == "active")
        #expect(sourceGone)
        #expect(hit)
    }
    
    @Test("a rebuild preserves ripple flags")
    func rebuildPreservesRippleFlags() throws {
        // When
        home.createNote(id: "rbm-note", content: "## Body\nbody here\n")
        
        // Then
        #expect(home.apply([["op": "flag", "id": "rbm-note",
            "kind": "reconsolidate", "reason": "preserved"]]).status == "ok")
        
        _ = try indexer.buildLocked(home.database(), home.brain, rebuild: true)
        
        let value = try home.read { db in
            try String.fetchOne(db, sql: "SELECT reason FROM ripple_flags WHERE note_id='rbm-note' AND flag='reconsolidate'")
        }
        
        #expect(value == "preserved")
    }
    
    @Test("a rebuild preserves the usage columns it cannot recompute")
    func rebuildPreservesNotesUsageColumns() throws {
        // Given
        home.createNote(id: "usage-note", content: "## a\nbody here\n")
        
        let queue = try home.storage.connect()
        
        try home.write { db in
            try db.execute(sql: "UPDATE note_usage SET hit_count=7, last_retrieved_at=1700000000 WHERE note_id='usage-note'")
        }
        
        _ = try indexer.buildLocked(home.database(), home.brain, rebuild: true)
        
        // When
        let (hitCount, lastRetrieved) = try home.read { db -> (Int, Int) in
            (try Int.fetchOne(db, sql: "SELECT hit_count FROM note_usage WHERE note_id='usage-note'") ?? -1,
                try Int.fetchOne(db, sql: "SELECT last_retrieved_at FROM note_usage WHERE note_id='usage-note'") ?? -1)
        }
        
        // Then
        #expect(hitCount == 7)
        #expect(lastRetrieved == 1700000000)
    }
    
    @Test("lifecycle events are pruned once they fall outside retention")
    func lifecycleEventsRetentionPrunes() throws {
        // Given
        home.createNote(id: "lc-note", content: "## a\nb\n")
        
        // When
        let queue = try home.storage.connect()
        let before = try queue.read { db in
            try Int.fetchOne(db, sql: "SELECT count(*) FROM note_lifecycle_events WHERE note_id='lc-note'") ?? 0
        }
        
        // Then
        #expect(before > 0)
        
        try queue.write { db in
            try db.execute(sql: "UPDATE note_lifecycle_events SET created_at = 1 WHERE note_id='lc-note'")
            
            _ = try PruneOldLifecycleEventsTransaction(now: 1_000_000_000, retentionDays: 180).perform(db)
        }
        
        let after = try queue.read { db in
            try Int.fetchOne(db, sql: "SELECT count(*) FROM note_lifecycle_events WHERE note_id='lc-note'") ?? -1
        }
        
        #expect(after == 0)
    }
    
    @Test("reindexing preserves an entity hit count")
    func reindexPreservesEntityHitCount() throws {
        // Then
        #expect(home.apply([["op": "create_note", "id": "rc-note", "axis": "tech",
            "title": "t", "tags": ["tech"], "summary": "s",
            "content": "## a\nb\n", "entities": ["BAR-9"]]]).status == "ok")
        
        let path = try home.read { db in
            home.layout.relativeFile(forId: "rc-note")
        }
        
        try home.write { db in
            try db.execute(sql: "UPDATE entity_index SET hit_count=5 WHERE note_id='rc-note' AND entity='BAR-9'")
        }
        
        _ = try home.database().write { db in try indexer.reindexFiles(db, home.brain, filePaths: [path]) }
        
        let hitCount = try home.read { db in
            try Int.fetchOne(db, sql: "SELECT hit_count FROM entity_index WHERE note_id='rc-note' AND entity='BAR-9'") ?? -1
        }
        
        #expect(hitCount == 5)
    }
    
    @Test("a rebuild preserves it too")
    func rebuildPreservesEntityHitCount() throws {
        // Then
        #expect(home.apply([["op": "create_note", "id": "eh-note", "axis": "tech",
            "title": "t", "tags": ["tech"], "summary": "s",
            "content": "## a\nb\n", "entities": ["FOO-1"]]]).status == "ok")
        
        let queue = try home.storage.connect()
        
        try home.write { db in
            try db.execute(sql: "UPDATE entity_index SET hit_count=9 WHERE note_id='eh-note' AND entity='FOO-1'")
        }
        
        _ = try indexer.buildLocked(home.database(), home.brain, rebuild: true)
        
        let hitCount = try home.read { db in
            try Int.fetchOne(db, sql: "SELECT hit_count FROM entity_index WHERE note_id='eh-note' AND entity='FOO-1'") ?? -1
        }
        
        #expect(hitCount == 9)
    }
    
    @Test("a rebuild regenerates the entity index itself, which is derived from the body")
    func rebuildRegeneratesEntityIndex() throws {
        // Then
        #expect(home.apply([["op": "create_note", "id": "ent-note", "axis": "tech",
            "title": "t", "tags": ["tech"], "summary": "s",
            "content": "## a\nbody\n", "entities": ["BKIOS-999", "kim-cs"]]]).status == "ok")
        
        let queue = try home.storage.connect()
        let before = try home.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM entity_index WHERE note_id='ent-note'") ?? 0
        }
        
        #expect(before == 2)
        
        _ = try indexer.buildLocked(home.database(), home.brain, rebuild: true)
        
        let after = try home.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM entity_index WHERE note_id='ent-note'") ?? 0
        }
        
        #expect(after == 2)
    }
    
    @Test("a rebuild preserves the links it cannot derive from a body")
    func rebuildPreservesNonReferenceLinks() throws {
        // Given
        home.createNote(id: "co-a", content: "## Body\nalpha body\n")
        home.createNote(id: "co-b", content: "## Body\nbravo body\n")
        
        let queue = try home.storage.connect()
        
        try home.write { db in
            try db.execute(sql: """
                INSERT OR IGNORE INTO note_links (src, dst, kind, weight, created_at, last_activated_at)
                VALUES ('co-a','co-b','cooccur', 1.0, 1700000000, 1700000000)
                """)
        }
        
        _ = try indexer.buildLocked(home.database(), home.brain, rebuild: true)
        
        // When
        let survived = try home.read { db in
            (try Int.fetchOne(db, sql:
                "SELECT COUNT(*) FROM note_links WHERE kind='cooccur' AND src='co-a' AND dst='co-b'") ?? 0) > 0
        }
        
        // Then
        #expect(survived)
    }
    
    @Test("a split fails loud on an artifact it has no routing rule for")
    func splitFailLoudOnNonTermArtifact() throws {
        // When
        home.createNote(id: "spm-src", content: "## A\nalpha content\n## B\nbravo content\n")
        
        // Then
        home.createNote(id: "spm-nbr", content: "## N\nneighbor content\n")
        #expect(home.apply([["op": "propose_link", "src": "spm-src", "dst": "spm-nbr",
            "kind": "assoc", "confidence": 0.9, "provenance": "t"]]).status == "ok")
        
        let into: [[String: Any]] = [
            ["id": "spm-a", "title": "A", "tags": ["flow"], "summary": "s", "sections": ["## A"]],
            ["id": "spm-b", "title": "B", "tags": ["flow"], "summary": "s", "sections": ["## B"]]
        ]
        
        #expect(home.apply([["op": "split_note", "from_id": "spm-src", "into": into]]).status != "ok")
    }
    
    @Test("an alias nothing in the corpus supports is quarantined rather than indexed")
    func hallucinatedAliasQuarantinedAsPending() throws {
        // Given
        home.createNote(id: "enr-h1", content: "## Body\nordinary words about things\n")
        
        // When
        let result = home.apply([[
            "op": "add_retrieval_terms", "id": "enr-h1",
            "kind": "alias", "terms": ["xqzplmwvb"]
        ]])
        
        // Then
        #expect(result.status == "ok")
        
        let queue = try home.storage.connect()
        let row = try queue.read { db in
            try Row.fetchOne(db, sql: """
                SELECT status, reject_reason FROM note_retrieval_terms
                WHERE note_id = 'enr-h1' AND kind = 'alias'
                """)
        }
        
        #expect((row?["status"] as String?) == "pending")
        #expect((row?["reject_reason"] as String?) == nil)
        
        let hit = try queue.read { db in
            try String.fetchAll(db, sql: "SELECT id FROM notes_fts WHERE notes_fts MATCH ?",
                arguments: ["\"xqzplmwvb\""])
        }
        
        #expect(!hit.contains("enr-h1"))
    }
    
    @Test("a synonym that does not appear in the body can still activate — that is what an alias is for")
    func synonymAliasNotInBodyActivates() throws {
        // Given
        home.createNote(id: "enr-syn-a", content: "## A\nlunar trajectory specific content\n")
        home.createNote(id: "enr-syn-b", content: "## B\norbital mechanics elsewhere\n")
        
        // When
        let result = home.apply([[
            "op": "add_retrieval_terms", "id": "enr-syn-a",
            "kind": "alias", "terms": ["orbital"]
        ]])
        
        // Then
        #expect(result.status == "ok")
        
        let queue = try home.storage.connect()
        let status = try queue.read { db in
            try String.fetchOne(db, sql: """
                SELECT status FROM note_retrieval_terms WHERE note_id = 'enr-syn-a'
                """)
        }
        
        #expect(status == "active")
        
        let hit = try queue.read { db in
            try String.fetchAll(db, sql: "SELECT id FROM notes_fts WHERE notes_fts MATCH ?",
                arguments: ["\"orbital\""])
        }
        
        #expect(hit.contains("enr-syn-a"))
    }
    
    @Test("a term too common to discriminate is rejected")
    func commonAliasRejectedAsIdfCommon() throws {
        // Given
        for index in 0..<10 {
            home.createNote(id: "enr-c\(index)", content: "## Body\nubiquitoustoken note body \(index)\n")
        }
        
        // When
        let result = home.apply([[
            "op": "add_retrieval_terms", "id": "enr-c0",
            "kind": "alias", "terms": ["ubiquitoustoken"]
        ]])
        
        // Then
        #expect(result.status == "ok")
        
        let queue = try home.storage.connect()
        let row = try queue.read { db in
            try Row.fetchOne(db, sql: """
                SELECT status, reject_reason FROM note_retrieval_terms
                WHERE note_id = 'enr-c0' AND kind = 'alias'
                """)
        }
        
        #expect((row?["status"] as String?) == "rejected")
        #expect((row?["reject_reason"] as String?) == "idf_common")
    }
    
    @Test("a stale note does not count toward document frequency")
    func staleNotesDontInflateIdfDf() throws {
        // Given
        for index in 0..<9 {
            home.createNote(id: "sg-live\(index)", content: "## Body\nfiller distinct body \(index)\n")
        }
        
        home.createNote(id: "sg-target", content: "## Body\nsurfacetoken note body\n")
        
        for index in 0..<10 {
            home.createNote(id: "sg-stale\(index)", content: "## Body\nsurfacetoken stale body \(index)\n")
        }
        
        let queue = try home.storage.connect()
        
        try queue.write { db in
            for index in 0..<10 {
                try db.execute(sql: "UPDATE notes SET stale = 1 WHERE id = ?",
                    arguments: ["sg-stale\(index)"])
            }
        }
        
        // When
        let result = home.apply([[
            "op": "add_retrieval_terms", "id": "sg-target",
            "kind": "alias", "terms": ["surfacetoken"]
        ]])
        
        // Then
        #expect(result.status == "ok")
        
        let status = try queue.read { db in
            try String.fetchOne(db, sql: """
                SELECT status FROM note_retrieval_terms WHERE note_id = 'sg-target' AND kind = 'alias'
                """)
        }
        
        #expect(status == "active")
    }
    
    // propose_link
    // JSONSerialization decodes `true` to an NSNumber, and `NSNumber as? Double`
    // succeeds with 1.0 — so a hand-rolled cast records maximum confidence for a
    // caller who never named a number.
    @Test("a bool is not a confidence — `true` is refused, not read as 1.0")
    func proposeLinkRefusesBoolConfidence() throws {
        // Given
        home.createNote(id: "enr-pl-bool-a")
        home.createNote(id: "enr-pl-bool-b")

        // When
        let result = home.apply([[
            "op": "propose_link", "src": "enr-pl-bool-a", "dst": "enr-pl-bool-b",
            "confidence": true, "provenance": "test:capture"
        ]])

        // Then
        #expect(result.status == "rejected", "a bool confidence must not be read as a number")
        #expect(result.error.contains("confidence must be a number"), "unexpected: \(result.error)")

        let queue = try home.storage.connect()
        let count = try queue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM note_links WHERE kind = 'assoc'") ?? 0
        }

        #expect(count == 0, "a refused op must leave no edge behind")
    }

    // The refusal above must not reach past bools. `raw is Bool` answers by
    // value, so an NSNumber holding 1 satisfies it — and 1 is exactly the
    // upper bound the schema states.
    @Test("the integer 1 is a confidence — the bool refusal does not reach it")
    func proposeLinkAcceptsIntegerConfidence() throws {
        // Given
        home.createNote(id: "enr-pl-int-a")
        home.createNote(id: "enr-pl-int-b")

        // When
        let result = home.apply([[
            "op": "propose_link", "src": "enr-pl-int-a", "dst": "enr-pl-int-b",
            "confidence": 1, "provenance": "test:capture"
        ]])

        // Then
        #expect(result.status == "ok", "unexpected: \(result.error)")

        let queue = try home.storage.connect()
        let weight = try queue.read { db in
            try Double.fetchOne(db, sql: "SELECT weight FROM note_links WHERE kind = 'assoc'") ?? 0
        }

        #expect(weight > 0.45, "confidence 1 must position the edge at the top of the dormant band")
    }

    @Test("a proposed edge enters dormant, so the decay loop is its validator")
    func proposeLinkInsertsDormantAssocEdge() throws {
        // Given
        home.createNote(id: "enr-pl-a")
        home.createNote(id: "enr-pl-b")
        
        // When
        let result = home.apply([[
            "op": "propose_link", "src": "enr-pl-a", "dst": "enr-pl-b",
            "confidence": 0.8, "provenance": "test:capture"
        ]])
        
        // Then
        #expect(result.status == "ok")
        
        let queue = try home.storage.connect()
        let row = try queue.read { db in
            try Row.fetchOne(db, sql: """
                SELECT weight, provenance FROM note_links WHERE kind = 'assoc'
                """)
        }
        let weight = row?["weight"] as Double? ?? 0
        
        #expect(abs(weight - 0.454) < 0.001)
        #expect((row?["provenance"] as String?) == "test:capture")
        
        let assocExpanded = try home.database().read { db in try ExpandLinksTransaction(noteIds: ["enr-pl-a"], hops: 1, kind: .assoc, minWeight: home.retrievalTuning.neighborFloor, siblingDiscount: home.retrievalTuning.siblingDiscount).perform(db) }
        
        #expect(!assocExpanded.contains { hit in hit.id == "enr-pl-b" })
        
        _ = try home.database().write { db in try StrengthenLinksTransaction(pairs: [("enr-pl-a", "enr-pl-b")], kind: .assoc, step: 0.3).perform(db) }
        
        let after = try home.database().read { db in try ExpandLinksTransaction(noteIds: ["enr-pl-a"], hops: 1, kind: .assoc, minWeight: home.retrievalTuning.neighborFloor, siblingDiscount: home.retrievalTuning.siblingDiscount).perform(db) }
        
        #expect(after.contains { hit in hit.id == "enr-pl-b" })
    }
    
    @Test("a note cannot be proposed as an association with itself")
    func proposeLinkRejectsSelfLoop() throws {
        // Given
        home.createNote(id: "enr-self")
        
        // When
        let result = home.apply([[
            "op": "propose_link", "src": "enr-self", "dst": "enr-self"
        ]])
        
        // Then
        #expect(result.status != "ok")
    }
    
    // purge_enrichment
    @Test("purging by provenance recalls exactly what that run produced")
    func purgeEnrichmentRecallsProvenance() throws {
        // Given
        home.createNote(id: "enr-pg-a", content: "## Body\nflywheel resonance distinctive\n")
        home.createNote(id: "enr-pg-b")
        
        _ = home.apply([[
            "op": "add_retrieval_terms", "id": "enr-pg-a",
            "kind": "alias", "terms": ["flywheel resonance"],
            "provenance": "noisy:model"
        ]])
        _ = home.apply([[
            "op": "propose_link", "src": "enr-pg-a", "dst": "enr-pg-b",
            "provenance": "noisy:model"
        ]])
        
        // When
        let result = home.apply([[
            "op": "purge_enrichment", "provenance": "noisy:model"
        ]])
        
        // Then
        #expect(result.status == "ok")
        
        let queue = try home.storage.connect()
        let termStatus = try queue.read { db in
            try String.fetchOne(db, sql: """
                SELECT status FROM note_retrieval_terms WHERE provenance = 'noisy:model'
                """)
        }
        
        #expect(termStatus == "rejected")
        
        let edgeCount = try queue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM note_links WHERE provenance = 'noisy:model'") ?? -1
        }
        
        #expect(edgeCount == 0)
    }
    
    // validation pass directly
    @Test("a quarantined term that never finds support is rejected once its window passes")
    func quarantinedTermRejectedAfterStaleWindow() throws {
        // Given
        home.createNote(id: "enr-pd1", content: "## Body\napple banana cherry\n")
        
        _ = home.apply([[
            "op": "add_retrieval_terms", "id": "enr-pd1",
            "kind": "alias", "terms": ["zzqqxxnovel"]
        ]])
        
        // When
        let queue = try home.storage.connect()
        let status = try queue.read { db in
            try String.fetchOne(db, sql: """
                SELECT status FROM note_retrieval_terms WHERE note_id = 'enr-pd1'
                """)
        }
        
        // Then
        #expect(status == "pending")
        
        let rejected = try home.storage.writeLock { () -> Int in
            let writeQueue = try home.storage.connect()
            
            return try writeQueue.write { db in try RejectStalePendingTermsTransaction(maxAgeSec: 0).perform(db) }
        }
        
        #expect(rejected >= 1)
    }
    
    @Test("a merge leaves undirected edges canonical, so none is stored twice")
    func mergeNormalizesUndirectedEdges() throws {
        // Given
        home.createNote(id: "ued-a", content: "## Body\nalpha body\n")
        home.createNote(id: "ued-m", content: "## Body\nmiddle body\n")
        home.createNote(id: "ued-z", content: "## Body\nzulu body\n")
        
        let queue = try home.storage.connect()
        
        try queue.write { db in
            try db.execute(sql: """
                INSERT OR IGNORE INTO note_links (src, dst, kind, weight, created_at, last_activated_at)
                VALUES ('ued-a','ued-m','cooccur',1.0,1700000000,1700000000)
                """)
        }
        
        // When
        let result = home.apply([[
            "op": "merge_notes", "into_id": "ued-z", "from_ids": ["ued-a"],
            "merged_content": "## Body\nzulu body\nalpha body\n",
            "summary": "merged", "tags": ["tech"]
        ]])
        
        // Then
        #expect(result.status == "ok")
        
        let (canonical, denormalized) = try queue.read { db -> (Int, Int) in
            let canonical = try Int.fetchOne(db,
                sql: "SELECT COUNT(*) FROM note_links WHERE kind='cooccur' AND src='ued-m' AND dst='ued-z'") ?? 0
            let denormalized = try Int.fetchOne(db,
                sql: "SELECT COUNT(*) FROM note_links WHERE kind='cooccur' AND src='ued-z' AND dst='ued-m'") ?? 0
            
            return (canonical, denormalized)
        }
        
        #expect(canonical == 1)
        #expect(denormalized == 0)
    }
    
    @Test("when both notes knew the same neighbour, their weights add rather than one replacing the other")
    func mergeAccumulatesSharedNeighborWeight() throws {
        // Given
        home.createNote(id: "mwa-from", tags: ["tech"], content: "## Body\nalpha body\n")
        home.createNote(id: "mwa-into", tags: ["persona"], content: "## Body\ninto body\n")
        home.createNote(id: "mwa-nbr", tags: ["env"], content: "## Body\nneighbor body\n")
        
        let queue = try home.storage.connect()
        
        try queue.write { db in
            try db.execute(sql: """
                INSERT INTO note_links (src, dst, kind, weight, created_at, last_activated_at)
                VALUES ('mwa-from','mwa-nbr','cooccur',0.5,1700000000,1700000000),
                       ('mwa-into','mwa-nbr','cooccur',0.3,1700000000,1700000000)
                """)
        }
        
        // When
        let result = home.apply([[
            "op": "merge_notes", "into_id": "mwa-into", "from_ids": ["mwa-from"],
            "merged_content": "## Body\ninto body\nalpha body\n",
            "summary": "merged", "tags": ["persona"]
        ]])
        
        // Then
        #expect(result.status == "ok")
        
        let (weight, fromEdges) = try queue.read { db -> (Double, Int) in
            let weight = try Double.fetchOne(db, sql: """
                SELECT weight FROM note_links WHERE kind='cooccur'
                  AND ((src='mwa-into' AND dst='mwa-nbr') OR (src='mwa-nbr' AND dst='mwa-into'))
                """) ?? -1
            let fromEdges = try Int.fetchOne(db,
                sql: "SELECT COUNT(*) FROM note_links WHERE src='mwa-from' OR dst='mwa-from'") ?? -1
            
            return (weight, fromEdges)
        }
        
        #expect(abs(weight - 0.8) < 1e-9, "shared-neighbor weight not accumulated (0.3 + 0.5 = 0.8)")
        #expect(fromEdges == 0, "merged-away source still has edges")
    }
    
    @Test("a term's status after a merge is the stronger of the two, not the last one written")
    func mergeReconcilesRetrievalTermStatusPriority() throws {
        // Given
        home.createNote(id: "nrt-from", content: "## Body\nfrom body\n")
        home.createNote(id: "nrt-into", content: "## Body\ninto body\n")
        
        let queue = try home.storage.connect()
        
        try queue.write { db in
            try db.execute(sql: """
                INSERT INTO note_retrieval_terms (note_id, kind, term, status, provenance, created_at)
                VALUES ('nrt-from', 'alias', 'shared-term', 'active', 'forge:capture:from', 1700000000)
                """)
            try db.execute(sql: """
                INSERT INTO note_retrieval_terms (note_id, kind, term, status, reject_reason, created_at)
                VALUES ('nrt-into', 'alias', 'shared-term', 'rejected', 'idf_common', 1700000001)
                """)
        }
        
        // When
        let result = home.apply([[
            "op": "merge_notes", "into_id": "nrt-into", "from_ids": ["nrt-from"],
            "merged_content": "## Body\ninto body\nfrom body\n",
            "summary": "merged", "tags": ["flow"]
        ]])
        
        // Then
        #expect(result.status == "ok")
        
        let (status, provenance, rowCount) = try queue.read { db -> (String?, String?, Int) in
            let status = try String.fetchOne(db, sql: """
                SELECT status FROM note_retrieval_terms WHERE note_id = 'nrt-into' AND kind = 'alias' AND term = 'shared-term'
                """)
            let provenance = try String.fetchOne(db, sql: """
                SELECT provenance FROM note_retrieval_terms WHERE note_id = 'nrt-into' AND kind = 'alias' AND term = 'shared-term'
                """)
            let count = try Int.fetchOne(db, sql:
                "SELECT COUNT(*) FROM note_retrieval_terms WHERE note_id IN ('nrt-from', 'nrt-into')") ?? -1
            
            return (status, provenance, count)
        }
        
        #expect(status == "active", "higher-priority status (active) must win over into's rejected copy")
        #expect(provenance == "forge:capture:from", "winning row's provenance must carry over, not be dropped")
        #expect(rowCount == 1, "colliding rows must reconcile to one, not silently vanish under cascade delete")
    }
    
    @Test("a flag resolved on either side stays resolved, and the counts accumulate")
    func mergeReconcilesRippleFlagResolvedPriorityAndAccumulatesCount() throws {
        // Given
        home.createNote(id: "rpf-from", content: "## Body\nfrom body\n")
        home.createNote(id: "rpf-into", content: "## Body\ninto body\n")
        
        let queue = try home.storage.connect()
        
        try queue.write { db in
            try db.execute(sql: """
                INSERT INTO ripple_flags (note_id, flag, reason, created_at, last_flagged_at, flag_count, resolved_at)
                VALUES ('rpf-from', 'stale_ref', 'from reason', 1700000000, 1700000300, 3, NULL)
                """)
            try db.execute(sql: """
                INSERT INTO ripple_flags (note_id, flag, reason, created_at, last_flagged_at, flag_count, resolved_at)
                VALUES ('rpf-into', 'stale_ref', 'into reason', 1700000100, 1700000200, 1, 1700000250)
                """)
        }
        
        // When
        let result = home.apply([[
            "op": "merge_notes", "into_id": "rpf-into", "from_ids": ["rpf-from"],
            "merged_content": "## Body\ninto body\nfrom body\n",
            "summary": "merged", "tags": ["flow"]
        ]])
        
        // Then
        #expect(result.status == "ok")
        
        let (resolvedAt, flagCount, reason, createdAt, lastFlaggedAt, rowCount) = try queue.read { db -> (Int?, Int, String?, Int, Int, Int) in
            let row = try Row.fetchOne(db, sql: """
                SELECT resolved_at, flag_count, reason, created_at, last_flagged_at
                FROM ripple_flags WHERE note_id = 'rpf-into' AND flag = 'stale_ref'
                """)!
            let count = try Int.fetchOne(db, sql:
                "SELECT COUNT(*) FROM ripple_flags WHERE note_id IN ('rpf-from', 'rpf-into')") ?? -1
            
            return (row["resolved_at"], row["flag_count"], row["reason"], row["created_at"], row["last_flagged_at"], count)
        }
        
        #expect(resolvedAt == nil, "unresolved (from) must win over into's resolved copy")
        #expect(flagCount == 4, "flag_count must accumulate (3 + 1), not drop from's count")
        #expect(reason == "from reason", "reason must follow the more recent last_flagged_at (from)")
        #expect(createdAt == 1700000000, "created_at must keep the earliest")
        #expect(lastFlaggedAt == 1700000300, "last_flagged_at must take the max")
        #expect(rowCount == 1, "colliding rows must reconcile to one")
    }
    
    @Test("the surviving reason belongs to the same side as the surviving timestamp")
    func mergeCouplesRippleFlagReasonToSameWinnerAsResolvedAt() throws {
        // Given
        home.createNote(id: "rpf2-from", content: "## Body\nfrom body\n")
        home.createNote(id: "rpf2-into", content: "## Body\ninto body\n")
        
        let queue = try home.storage.connect()
        
        try queue.write { db in
            try db.execute(sql: """
                INSERT INTO ripple_flags (note_id, flag, reason, created_at, last_flagged_at, flag_count, resolved_at)
                VALUES ('rpf2-from', 'stale_ref', 'from reason (unresolved)', 1700000000, 1700000100, 1, NULL)
                """)
            try db.execute(sql: """
                INSERT INTO ripple_flags (note_id, flag, reason, created_at, last_flagged_at, flag_count, resolved_at)
                VALUES ('rpf2-into', 'stale_ref', 'into reason (resolved)', 1700000050, 1700000300, 1, 1700000350)
                """)
        }
        
        // When
        let result = home.apply([[
            "op": "merge_notes", "into_id": "rpf2-into", "from_ids": ["rpf2-from"],
            "merged_content": "## Body\ninto body\nfrom body\n",
            "summary": "merged", "tags": ["flow"]
        ]])
        
        // Then
        #expect(result.status == "ok")
        
        let (resolvedAt, reason) = try queue.read { db -> (Int?, String?) in
            let row = try Row.fetchOne(db, sql: """
                SELECT resolved_at, reason FROM ripple_flags WHERE note_id = 'rpf2-into' AND flag = 'stale_ref'
                """)!
            
            return (row["resolved_at"], row["reason"])
        }
        
        #expect(resolvedAt == nil, "unresolved (from) must win despite into having a newer last_flagged_at")
        #expect(reason == "from reason (unresolved)",
            "reason must follow the SAME winner as resolved_at (from), not whichever side has newer last_flagged_at")
    }
    
    @Test("dismiss counts accumulate and the freshest snapshot survives")
    func mergeAccumulatesDismissCountAndKeepsFreshestSnapshot() throws {
        // Given
        home.createNote(id: "cds-from", content: "## Body\nfrom body\n")
        home.createNote(id: "cds-into", content: "## Body\ninto body\n")
        
        let queue = try home.storage.connect()
        
        try queue.write { db in
            try db.execute(sql: """
                INSERT INTO candidate_dismissals (note_id, kind, dismiss_count, word_count, section_count, generation, reason, last_dismissed_at)
                VALUES ('cds-from', 'split', 2, 50, 4, 5, 'from reason', 1700000200)
                """)
            try db.execute(sql: """
                INSERT INTO candidate_dismissals (note_id, kind, dismiss_count, word_count, section_count, generation, reason, last_dismissed_at)
                VALUES ('cds-into', 'split', 1, 10, 1, 3, 'into reason', 1700000100)
                """)
        }
        
        // When
        let result = home.apply([[
            "op": "merge_notes", "into_id": "cds-into", "from_ids": ["cds-from"],
            "merged_content": "## Body\ninto body\nfrom body\n",
            "summary": "merged", "tags": ["flow"]
        ]])
        
        // Then
        #expect(result.status == "ok")
        
        let row = try queue.read { db in
            try Row.fetchOne(db, sql: """
                SELECT dismiss_count, word_count, generation, reason, last_dismissed_at
                FROM candidate_dismissals WHERE note_id = 'cds-into' AND kind = 'split'
                """)!
        }
        
        #expect((row["dismiss_count"] as Int) == 3, "dismiss_count must accumulate (2 + 1)")
        #expect((row["last_dismissed_at"] as Int) == 1700000200, "last_dismissed_at must take the max")
        #expect((row["word_count"] as Int) == 50, "snapshot fields must follow the freshest dismissal (from)")
        #expect((row["generation"] as Int) == 5, "generation must follow the freshest dismissal (from)")
        #expect((row["reason"] as String) == "from reason", "reason must follow the freshest dismissal (from)")
    }
    
    // FetchEntityHitsTransaction — archived/stale surfacing gate
    @Test("a stale note is left off the entity hit surface")
    func entityHitsExcludesStale() throws {
        // Given
        let ids = ["eh-act-0", "eh-act-1", "eh-act-2", "eh-arc-0", "eh-stl-0"]
        
        for id in ids {
            home.createNote(id: id, content: "## body\ntest entity EH-99 content\n")
        }
        
        let queue = try home.storage.connect()
        
        try queue.write { db in
            for id in ids {
                try db.execute(sql: """
                    INSERT OR IGNORE INTO entity_index (entity, note_id, last_seen_at, hit_count)
                    VALUES ('EH-99', ?, 1700000000, 1)
                    """, arguments: [id])
            }
            
            try db.execute(sql: "UPDATE notes SET stale = 1 WHERE id = 'eh-arc-0'")
            try db.execute(sql: "UPDATE notes SET stale = 1 WHERE id = 'eh-stl-0'")
        }
        
        // When
        let hits = try queue.read { db in try FetchEntityHitsTransaction(entities: ["EH-99"], limitPerEntity: 10).perform(db) }
        
        // Then
        #expect(hits.count == 3)
        
        let hitIds = hits.map { hit in hit.noteId }
        
        #expect(!hitIds.contains("eh-arc-0"))
        #expect(!hitIds.contains("eh-stl-0"))
    }
}
