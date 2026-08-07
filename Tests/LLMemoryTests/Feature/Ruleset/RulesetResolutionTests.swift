//
//  RulesetResolutionTests.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import Testing
@testable import LLMemory

// Which ruleset applies is resolved from two inputs. The lock exists so a caller cannot talk its way
// out of the ruleset an operator pinned, and it has to refuse rather than fall back when pinned to nothing.
@Suite("RulesetResolution Tests", .serialized)
struct RulesetResolutionTests {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Test
    @Test("with nothing set, nothing resolves — a blank argument is not a ruleset name")
    func bothUnsetReturnsNil() throws {
        // When
        try environment(ruleset: nil, locked: nil) {
            let fromNil = try RulesetResolution.resolve(cliRuleset: nil)
            let fromEmpty = try RulesetResolution.resolve(cliRuleset: "")
            let fromBlank = try RulesetResolution.resolve(cliRuleset: "   ")
        
        // Then
            #expect(fromNil == nil)
            #expect(fromEmpty == nil)
            #expect(fromBlank == nil)
        }
    }
    
    @Test("the caller's choice wins over the environment while the lock is off")
    func cliWinsWhenNotLocked() throws {
        // When
        try environment(ruleset: "env_one", locked: nil) {
            let withChoice = try RulesetResolution.resolve(cliRuleset: "cli_one")
            let withoutChoice = try RulesetResolution.resolve(cliRuleset: nil)
        
        // Then
            #expect(withChoice == "cli_one")
            #expect(withoutChoice == "env_one")
        }
    }
    
    @Test("the lock overrides the caller — that is the whole point of pinning one")
    func lockedIgnoresCli() throws {
        // When
        try environment(ruleset: "env_one", locked: "1") {
            let withChoice = try RulesetResolution.resolve(cliRuleset: "cli_one")
            let withoutChoice = try RulesetResolution.resolve(cliRuleset: nil)
        
        // Then
            #expect(withChoice == "env_one")
            #expect(withoutChoice == "env_one")
        }
    }
    
    @Test("a lock pinned to nothing is refused rather than quietly falling back to the caller")
    func lockedWithoutEnvRejects() throws {
        // Then
        try environment(ruleset: nil, locked: "1") {
            #expect(throws: RulesetResolution.Error.self) {
                _ = try RulesetResolution.resolve(cliRuleset: "cli_one")
            }
        }
    }
    
    @Test("the lock engages on any spelling of true", arguments: ["1", "true", "yes", "on", "TRUE", "Yes"])
    func lockedAcceptsVariousTruthy(raw: String) throws {
        // When
        try environment(ruleset: "env_one", locked: raw) {
            let resolved = try RulesetResolution.resolve(cliRuleset: "cli_one")
        
        // Then
            #expect(resolved == "env_one", "LOCKED=\(raw) should engage the lock")
        }
    }
    
    @Test("anything that is not true leaves the lock off, including nonsense",
        arguments: ["0", "false", "no", "off", "", "garbage"])
    func lockedFalsyDoesNotEngage(raw: String) throws {
        // When
        try environment(ruleset: "env_one", locked: raw) {
            let resolved = try RulesetResolution.resolve(cliRuleset: "cli_one")
        
        // Then
            #expect(resolved == "cli_one", "LOCKED=\(raw) should not engage the lock")
        }
    }
    
    // MARK: - Private
    private func environment(ruleset: String?, locked: String?, _ body: () throws -> Void) rethrows {
        try EnvironmentOverride([
            RulesetResolution.envRuleset: ruleset,
            RulesetResolution.envLocked: locked
        ])(body)
    }
}
