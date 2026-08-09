//
//  RulesetTests.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import Testing
import GRDB
@testable import LLMemory

// A ruleset narrows what ops may run on which axis. With none configured it fails open, because a
// brain with no policy must still be usable — but a rule that is present and malformed fails loud.
@Suite("Ruleset Tests", .serialized)
struct RulesetTests {
    // MARK: - Property
    private let home: MemoryHome
    
    // MARK: - Initializer
    init() throws {
        home = try MemoryHome()
    }
    
    // MARK: - Test
    @Test("with no ruleset configured everything is allowed")
    func emptyRulesetIsFailOpen() throws {
        // When
        let effective = try resolve(axis: "skill", rulesetIds: [])
        
        // Then
        #expect(effective.allows(op: "archive").ok)
        #expect(effective.opsWhitelist == nil)
        #expect(effective.opsDeny.isEmpty)
    }
    
    @Test("a whitelist of '*' allows every op")
    func whitelistStarAllowsEverything() throws {
        // Given
        try seedRuleset(id: "admin", rules: [("ops.whitelist", #"{"axis":"*","ops":["*"]}"#)])
        
        // When
        let effective = try resolve(axis: "skill", rulesetIds: ["admin"])
        
        // Then
        for op in ["archive", "create_note", "merge_notes", "delete_note"] {
            #expect(effective.allows(op: op).ok, "expected '\(op)' to pass under whitelist=['*']")
        }
    }
    
    @Test("a deny list narrows one axis and leaves the others as they were")
    func whitelistRestrictsOpsByAxis() throws {
        // Given
        try seedRuleset(id: "response", rules: [
            ("ops.whitelist", #"{"axis":"*","ops":["*"]}"#),
            ("ops.deny", #"{"axis":"skill","ops":["archive","delete_note"]}"#)
        ])
        
        // When
        let skill = try resolve(axis: "skill", rulesetIds: ["response"])
        let tech = try resolve(axis: "tech", rulesetIds: ["response"])
        
        // Then
        #expect(!skill.allows(op: "archive").ok)
        #expect(!skill.allows(op: "delete_note").ok)
        #expect(skill.allows(op: "patch_section").ok)
        #expect(tech.allows(op: "archive").ok, "the deny was scoped to one axis")
    }
    
    @Test("a deny of '*' blocks every op on that axis")
    func denyStarBlocksEverythingOnAxis() throws {
        // Given
        try seedRuleset(id: "consolidator", rules: [
            ("ops.whitelist", #"{"axis":"*","ops":["*"]}"#),
            ("ops.deny", #"{"axis":"spec","ops":["*"]}"#)
        ])
        
        // When
        let effective = try resolve(axis: "spec", rulesetIds: ["consolidator"])
        
        // Then
        for op in ["patch_section", "create_note", "archive"] {
            #expect(!effective.allows(op: op).ok, "expected '\(op)' to be denied under deny=['*']")
        }
    }
    
    @Test("a rule scoped to axis '*' applies on every axis")
    func axisStarRuleAppliesToAllAxes() throws {
        // Given
        try seedRuleset(id: "global_lock", rules: [
            ("ops.whitelist", #"{"axis":"*","ops":["patch_section"]}"#)
        ])
        
        // Then
        for axis in ["skill", "spec", "tech", "journal"] {
            let effective = try resolve(axis: axis, rulesetIds: ["global_lock"])
            
            #expect(effective.allows(op: "patch_section").ok)
            #expect(!effective.allows(op: "archive").ok)
        }
    }
    
    @Test("a rule for another axis is skipped — it does not narrow the axis being asked about")
    func nonMatchingAxisRulesAreSkipped() throws {
        // Given
        try seedRuleset(id: "mixed", rules: [
            ("ops.whitelist", #"{"axis":"skill","ops":["patch_section"]}"#)
        ])
        
        // When
        let tech = try resolve(axis: "tech", rulesetIds: ["mixed"])
        let skill = try resolve(axis: "skill", rulesetIds: ["mixed"])
        
        // Then
        #expect(tech.opsWhitelist == nil)
        #expect(tech.allows(op: "archive").ok)
        #expect(!skill.allows(op: "archive").ok)
        #expect(skill.allows(op: "patch_section").ok)
    }
    
    @Test("an unknown rule kind is ignored, so an older binary can still read a newer ruleset")
    func unknownRuleKindIsIgnored() throws {
        // Given
        try seedRuleset(id: "future", rules: [
            ("ops.whitelist", #"{"axis":"*","ops":["create_note"]}"#),
            ("ops.bogus.future", #"{"axis":"*","value":42}"#)
        ])
        
        // When
        let effective = try resolve(axis: "skill", rulesetIds: ["future"])
        
        // Then
        #expect(effective.allows(op: "create_note").ok)
        #expect(!effective.allows(op: "archive").ok, "the known rule still narrows the surface")
    }
    
    @Test("params that are not a JSON object are refused at write time, not at read time")
    func malformedParamsJSONIsRejectedAtWrite() throws {
        try write { database in
            try database.execute(
                sql: "INSERT INTO ruleset(id,name,description,created_at) VALUES ('rs-x','rs-x','',?)",
                arguments: [home.now]
            )
            
            #expect(throws: (any Error).self) {
                try database.execute(sql: """
                    INSERT INTO rule(ruleset_id,kind,params,enabled,created_at)
                    VALUES ('rs-x','ops.deny','not json',1,?)
                    """, arguments: [home.now])
            }
            #expect(throws: (any Error).self) {
                try database.execute(sql: """
                    INSERT INTO rule(ruleset_id,kind,params,enabled,created_at)
                    VALUES ('rs-x','ops.deny','[1,2]',1,?)
                    """, arguments: [home.now])
            }
        }
    }
    
    @Test("a rule whose value has the wrong type throws instead of failing open")
    func mistypedRuleParamsThrowInsteadOfFailOpen() throws {
        // Given
        try seedRuleset(id: "rs-shape", rules: [("ops.deny", #"{"axis":"*","ops":"delete_note"}"#)])
        
        // Then
        #expect(throws: RulesetService.RulesetError.self) {
            _ = try resolve(axis: "tech", rulesetIds: ["rs-shape"])
        }
    }
    
    @Test("a rule missing a required key throws instead of resolving to a narrower surface")
    func missingRequiredRuleKeyThrows() throws {
        // Given
        try seedRuleset(id: "rs-req", rules: [("ops.whitelist", #"{"axis":"*"}"#)])
        
        // Then
        #expect(throws: RulesetService.RulesetError.self) {
            _ = try resolve(axis: "tech", rulesetIds: ["rs-req"])
        }
    }
    
    @Test("an unknown consolidate mode throws rather than being read as one of the known ones")
    func unknownConsolidateModeThrows() throws {
        // Given
        try seedRuleset(id: "rs-mode", rules: [("consolidate.mode", #"{"axis":"*","mode":"paused"}"#)])
        
        // Then
        #expect(throws: RulesetService.RulesetError.self) {
            _ = try resolve(axis: "tech", rulesetIds: ["rs-mode"])
        }
    }
    
    @Test("existence reflects the row, so a typo'd ruleset id is answerable rather than silently empty")
    func rulesetExistsReflectsRow() throws {
        // Given
        try seedRuleset(id: "present", rules: [("ops.whitelist", #"{"axis":"*","ops":["*"]}"#)])
        
        // When
        let present = try home.read { database in try RulesetExistsTransaction(id: "present").perform(database) }
        let absent = try home.read { database in try RulesetExistsTransaction(id: "absent").perform(database) }
        
        // Then
        #expect(present)
        #expect(!absent)
    }
    
    // MARK: - Private
    private func seedRuleset(id: String, rules: [(kind: String, params: String)]) throws {
        try write { database in
            try database.execute(
                sql: "INSERT INTO ruleset(id,name,description,created_at) VALUES (?,?,?,?)",
                arguments: [id, id, "", home.now]
            )
            
            for rule in rules {
                try database.execute(sql: """
                    INSERT INTO rule(ruleset_id,kind,params,enabled,created_at) VALUES (?,?,?,1,?)
                    """, arguments: [id, rule.kind, rule.params, home.now])
            }
        }
    }
    
    private func write(_ body: (Database) throws -> Void) throws {
        try home.storage.writeLock { try home.database().write(body) }
    }
    
    private func resolve(axis: String, rulesetIds: [String]) throws -> RulesetService.Effective {
        try home.read { database in
            try home.container.ruleset.effective(GRDBReadScope(database), axis: axis, rulesetIds: rulesetIds)
        }
    }
}
