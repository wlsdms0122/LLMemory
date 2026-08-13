//
//  QueryCommandTests.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/8/26.
//

import Testing
import Foundation

@Suite("QueryCommand Tests", .serialized)
struct QueryCommandTests {
    // MARK: - Property
    private let brain: CLIBrain
    
    // MARK: - Initializer
    init() throws {
        brain = try CLIBrain(prefix: "llmemory-cli-query")
    }
    
    // MARK: - Test
    @Test("search matches a note by an entity token in its body")
    func searchFindsByToken() {
        // When
        let result = brain.run(["query", "search", "PIIMaskingTransformer", "--json"])
        
        // Then
        #expect(result.succeeded, "\(result.standardError)")
        #expect(result.ids().contains("tech.log-masking"))
    }
    
    @Test("a multi-keyword query is an OR of its tokens, not one phrase")
    func searchMultiKeywordUsesOR() {
        // When
        let result = brain.run(["query", "search", "TransferService PIIMaskingTransformer", "--json"])
        
        // Then
        let ids = Set(result.ids())
        
        #expect(result.succeeded, "\(result.standardError)")
        #expect(ids.contains("tech.log-masking"))
        #expect(ids.contains("flow.transfer-flow"))
    }
    
    @Test("--raw hands FTS5 operators through instead of quoting them away")
    func searchRawHonorsOperators() {
        // When
        let result = brain.run([
            "query", "search", "PIIMaskingTransformer NOT TransferService", "--raw", "--json"
        ])
        
        // Then
        let ids = Set(result.ids())
        
        #expect(result.succeeded, "\(result.standardError)")
        #expect(ids.contains("tech.log-masking"))
        #expect(!ids.contains("flow.transfer-flow"))
    }
    
    @Test("--tag narrows the result set to notes carrying that tag")
    func searchTagFilter() {
        // When
        let result = brain.run(["query", "search", "PIIMaskingTransformer", "--tag", "tech", "--json"])
        
        // Then
        let ids = Set(result.ids())
        
        #expect(result.succeeded, "\(result.standardError)")
        #expect(ids.contains("tech.log-masking"))
        #expect(!ids.contains("flow.transfer-flow"))
    }
    
    @Test("search hits carry a summary so the caller can pick the next hop")
    func searchHitsCarrySummary() {
        // When
        let result = brain.run(["query", "search", "PIIMaskingTransformer", "--json"])
        
        // Then
        let rows = result.rows()
        
        #expect(!rows.isEmpty)
        #expect(rows.allSatisfy { row in (row["summary"] as? String)?.isEmpty == false })
    }
    
    @Test("get returns the note body and the core-level stats")
    func getReturnsBodyAndCoreStats() {
        // When
        let result = brain.run(["query", "get", "tech.di-container", "--json"])
        
        // Then
        let row = (result.jsonArray() ?? []).first
        let stats = row?["stats"] as? [String: Any]
        
        #expect(result.succeeded, "\(result.standardError)")
        #expect(row?["id"] as? String == "tech.di-container")
        #expect((row?["body"] as? String ?? "").contains("TossDIContainer"))
        #expect(stats?["hit_count"] != nil)
        #expect(stats?["created_at"] == nil, "timestamps belong to the verbose level, not the core one")
    }
    
    @Test("--verbose adds the metadata level to get without changing the format")
    func getVerboseAddsTimestamps() {
        // When
        let result = brain.run(["query", "get", "tech.di-container", "--verbose", "--json"])
        
        // Then
        let stats = (result.jsonArray() ?? []).first?["stats"] as? [String: Any]
        
        #expect(result.succeeded, "\(result.standardError)")
        #expect(stats?["created_at"] != nil)
        #expect(stats?["edited_at"] != nil)
    }
    
    @Test("get reads several ids in one call")
    func getMultipleIds() {
        // When
        let result = brain.run(["query", "get", "tech.di-container", "flow.transfer-flow", "--json"])
        
        // Then
        #expect(result.succeeded, "\(result.standardError)")
        #expect((result.jsonArray() ?? []).count == 2)
    }
    
    @Test("an unknown id yields an empty result, not a leaked SQLite error")
    func getMissingIdReturnsNothing() {
        // When
        let result = brain.run(["query", "get", "no-such-note", "--json"])
        
        // Then
        #expect((result.jsonArray() ?? []).isEmpty)
        #expect(!result.standardError.contains("SQLite error"), "\(result.standardError)")
    }
    
    @Test("list --priority selects on the frontmatter field")
    func listEagerOnlyShowsEager() {
        // When
        let result = brain.run(["query", "list", "--priority", "eager", "--json"])
        
        // Then
        let ids = result.ids()
        
        #expect(result.succeeded, "\(result.standardError)")
        #expect(ids.contains("persona.tone"))
        #expect(!ids.contains("tech.di-container"))
    }
    
    @Test("list --tag selects on the tag")
    func listTagFilter() {
        // When
        let result = brain.run(["query", "list", "--tag", "tech", "--json"])
        
        // Then
        let ids = Set(result.ids())
        
        #expect(result.succeeded, "\(result.standardError)")
        #expect(ids.contains("tech.di-container"))
        #expect(ids.contains("tech.log-masking"))
        #expect(!ids.contains("flow.transfer-flow"))
    }
    
    @Test("list rows carry the id in JSON")
    func listJsonShape() {
        // When
        let result = brain.run(["query", "list", "--tag", "tech", "--json"])
        
        // Then
        let row = (result.jsonArray() ?? []).first
        
        #expect(result.succeeded, "\(result.standardError)")
        #expect(row?["id"] != nil)
    }
    
    @Test("level and format are orthogonal — core stays core in both JSON and plain")
    func listLevelIsOrthogonalToFormat() {
        // When
        let core = brain.run(["query", "list", "--tag", "tech", "--json"])
        let verbose = brain.run(["query", "list", "--tag", "tech", "--verbose", "--json"])
        let verbosePlain = brain.run(["query", "list", "--tag", "tech", "--verbose"])
        
        // Then
        let coreRow = core.jsonArray()?.first ?? [:]
        let verboseRow = verbose.jsonArray()?.first ?? [:]
        let plainHeader = verbosePlain.standardOutput.split(separator: "\n").first ?? ""
        
        #expect(core.succeeded, "\(core.standardError)")
        #expect(coreRow["summary"] != nil || coreRow["title"] != nil)
        #expect(coreRow["priority"] == nil && coreRow["created_at"] == nil)
        #expect(verboseRow["priority"] != nil)
        #expect(verboseRow["created_at"] != nil)
        #expect(verboseRow["edited_at"] != nil)
        #expect(plainHeader.contains("priority"))
        #expect(plainHeader.contains("created"))
    }
    
    @Test("plain list is a table that carries the summary column")
    func listPlainCarriesSummary() {
        // When
        let result = brain.run(["query", "list", "--tag", "tech"])
        
        // Then
        let lines = result.standardOutput.split(separator: "\n").map(String.init)
        
        #expect(result.succeeded, "\(result.standardError)")
        #expect(lines.first?.contains("summary") == true)
        #expect(lines.contains { line in line.contains("tech.log-masking") })
        #expect(result.standardOutput.contains("Transformer"))
    }
    
    @Test("--field selects on a custom frontmatter field, by key and by key=value")
    func listCustomFieldFilter() {
        // Given
        _ = brain.run([
            "operations", "apply", "--input",
            #"{"ops":[{"op":"set_frontmatter","id":"journal.old-journal","fields":{"affect":"high"}}],"rationale":"t"}"#
        ])
        
        // When
        let byKey = brain.run(["query", "list", "--field", "affect", "--json"])
        let byValue = brain.run(["query", "list", "--field", "affect=high", "--json"])
        let byOtherValue = brain.run(["query", "list", "--field", "affect=low", "--json"])
        
        // Then
        #expect(byKey.succeeded, "\(byKey.standardError)")
        #expect(Set(byKey.ids()) == ["journal.old-journal"])
        #expect(Set(byValue.ids()) == ["journal.old-journal"])
        #expect(byOtherValue.ids().isEmpty)
    }
    
    @Test("--source-stale resolves against the note_source join")
    func listSourceStaleSelectsNothingWhenNoSourceIsStale() {
        // When
        let result = brain.run(["query", "list", "--source-stale", "--json"])
        
        // Then
        #expect(result.succeeded, "\(result.standardError)")
        #expect(result.ids().isEmpty, "the seed declares no sources, so nothing can be source-stale")
    }
    
    @Test("stats counts the corpus and reports hit aggregates")
    func statsOverallCounts() {
        // When
        let result = brain.run(["query", "stats", "--json"])
        
        // Then
        let object = result.jsonObject()
        
        #expect(result.succeeded, "\(result.standardError)")
        #expect((object?["total"] as? Int ?? 0) >= 5)
        #expect(object?.keys.contains { key in key.contains("hit") } == true)
    }
    
    @Test("stats --prefix counts only that branch of the address space")
    func statsPrefixFilter() {
        // When
        let result = brain.run(["query", "stats", "--prefix", "tech", "--json"])
        
        // Then
        let object = result.jsonObject()
        
        #expect(result.succeeded, "\(result.standardError)")
        #expect((object?["total"] as? Int ?? 0) == 2, "the seed puts exactly two notes under tech")
        #expect(object?["total_hits"] != nil)
    }
    
    @Test("structure without a prefix reports the top level of the tree with counts")
    func structureReportsTopLevelTree() {
        // When
        let result = brain.run(["query", "structure", "--json"])
        
        // Then
        let tree = result.jsonObject()?["tree"] as? [[Any]] ?? []
        let tech = tree.first { row in row.first as? String == "tech" }
        
        #expect(result.succeeded, "\(result.standardError)")
        #expect(tech?.last as? Int == 2, "the seed puts exactly two notes under tech")
    }
    
    @Test("structure --prefix descends into that one branch instead")
    func structureScopedToOnePrefix() {
        // When
        let result = brain.run(["query", "structure", "--prefix", "tech", "--json"])
        
        // Then
        #expect(result.succeeded, "\(result.standardError)")
        #expect(result.jsonObject()?["prefix_stats"] != nil, "\(result.standardOutput)")
    }
    
    @Test("tree descends one level at a time, counting everything below each branch")
    func treeDescendsOneLevel() {
        // When
        let top = brain.run(["query", "tree", "--json"])
        let under = brain.run(["query", "tree", "--prefix", "tech", "--json"])
        
        // Then
        let topRows = top.jsonArrayOfArrays() ?? []
        let underRows = under.jsonArrayOfArrays() ?? []
        
        #expect(top.succeeded, "\(top.standardError)")
        #expect(topRows.contains { row in row.first as? String == "tech" && row.last as? Int == 2 })
        #expect(under.succeeded, "\(under.standardError)")
        #expect(Set(underRows.compactMap { row in row.first as? String })
            == ["tech.di-container", "tech.log-masking"])
    }
    
    @Test("entity resolves an entity name back to the notes that declare it")
    func entityReverseLookup() {
        // When
        let result = brain.run(["query", "entity", "PIIMaskingTransformer", "--json"])
        
        // Then
        let rows = result.jsonArray() ?? []
        let ids = Set(rows.compactMap { row in row["note_id"] as? String })
        
        #expect(result.succeeded, "\(result.standardError)")
        #expect(ids == ["tech.di-container", "tech.log-masking"])
        #expect(rows.allSatisfy { row in (row["summary"] as? String)?.isEmpty == false })
    }
    
    @Test("entity without a name lists every known entity")
    func entityListAll() {
        // When
        let result = brain.run(["query", "entity", "--json"])
        
        // Then
        #expect(result.succeeded, "\(result.standardError)")
        #expect((result.jsonArray()?.count ?? 0) >= 1)
    }
    
    @Test("neighbors walks the link graph and carries a summary per hop")
    func neighborsCarrySummary() {
        // When
        let result = brain.run(["query", "neighbors", "--id", "tech.di-container", "--json"])
        
        // Then
        let rows = result.jsonArray() ?? []
        
        #expect(result.succeeded, "\(result.standardError)")
        #expect(rows.contains { row in row["id"] as? String == "tech.log-masking" },
            "the seed links di-container to log-masking")
        #expect(rows.allSatisfy { row in (row["summary"] as? String)?.isEmpty == false })
    }
    
    @Test("related takes a free-text cue and surfaces the matching notes")
    func relatedFromText() {
        // When
        let result = brain.run([
            "query", "related", "--input", #"{"text":"PIIMaskingTransformer 로그 마스킹"}"#, "--json"
        ])
        
        // Then — a cue can land through any associative section, so accept the union rather than
        // pinning the test to whichever path happens to win today.
        let object = result.jsonObject()
        let surfaced = ["similar", "linked", "vector_linked", "entity_hits"]
            .flatMap { section in object?[section] as? [[String: Any]] ?? [] }
            .compactMap { row in row["id"] as? String }
        
        #expect(result.succeeded, "\(result.standardError)")
        #expect(Set(surfaced).contains("tech.log-masking"), "\(result.standardOutput)")
    }
    
    @Test("history replays the lifecycle events recorded for a note")
    func historyShowsLifecycle() {
        // When
        let result = brain.run(["query", "history", "--id", "tech.di-container", "--json"])
        
        // Then
        #expect(result.succeeded, "\(result.standardError)")
        #expect((result.jsonArray()?.count ?? 0) >= 1)
    }
    
    @Test("lint exits 0 or 1 — 1 means findings, not a crash")
    func lintReportsFindingsWithoutCrashing() {
        // When
        let result = brain.run(["query", "lint", "--json"])
        
        // Then
        #expect(result.succeeded || result.exitCode == 1, "\(result.standardError)")
        #expect(!result.standardError.contains("SQLite error"), "\(result.standardError)")
    }
    
    @Test("enrichment reports the terms and edges planted by the seed")
    func enrichmentObservesSeededState() {
        // When
        let result = brain.run(["query", "enrichment", "--json"])
        
        // Then
        #expect(result.succeeded, "\(result.standardError)")
        #expect(result.standardOutput.contains("test:seed"), "\(result.standardOutput)")
    }
}
