//
//  Options.swift
//  LLMemoryCLI
//
//  Created by JSilver on 8/7/26.
//

import ArgumentParser
import Foundation
import LLMemory

struct GlobalHomeOptions: ParsableArguments {
    // MARK: - Property
    @Option(
        name: .long,
        help: ArgumentHelp(
            "Brain home path (must contain data/ and cortex/).",
            discussion: """
                Required. Place AFTER the leaf subcommand (e.g. \
                `llmemory query stats --home brain`).
                """,
            valueName: "state-root"
        )
    )
    var home: String = ""
    
    @Option(
        name: .long,
        help: ArgumentHelp(
            "Session id for priming/event trace.",
            discussion: """
                Overrides MEMORY_SESSION_ID env. Stable across calls within \
                the same conversation/thread. Owner is normally the runtime \
                (ambient via env); use this flag for debug/override.
                """,
            valueName: "id"
        )
    )
    var sessionId: String = ""
    
    // MARK: - Initializer
    // MARK: - Public
    func validate() throws {
        if home.isEmpty {
            throw ValidationError("--home <path> required (place after the leaf subcommand)")
        }
    }
    
    // MARK: - Private
}

struct RulesetOption: ParsableArguments {
    // MARK: - Property
    @Option(
        name: .long,
        help: ArgumentHelp(
            "Mutation policy id that gates this transaction.",
            discussion: """
                Resolution: LLMEMORY_RULESET_LOCKED=1 forces the env value \
                LLMEMORY_RULESET (empty env ⇒ reject); otherwise this flag wins \
                over env, env over no policy. Unset ⇒ no gating.

                See `llmemory ruleset list` for defined policies.
                """,
            valueName: "id"
        )
    )
    var ruleset: String = ""
    
    var rulesetId: String? {
        let trimmed = ruleset.trimmingCharacters(in: .whitespacesAndNewlines)
        
        return trimmed.isEmpty ? nil : trimmed
    }
    
    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}

struct OutputFormat: ParsableArguments {
    // MARK: - Property
    @Flag(name: .long, help: "Emit JSON instead of plain text.")
    var json: Bool = false
    
    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}
