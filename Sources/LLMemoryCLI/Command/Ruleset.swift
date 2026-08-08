//
//  Ruleset.swift
//  LLMemoryCLI
//
//  Created by JSilver on 8/7/26.
//

import ArgumentParser
import Foundation
import LLMemory

struct RulesetCommand: ParsableCommand {
    // MARK: - Property
    static let configuration = CommandConfiguration(
        commandName: "ruleset",
        abstract: "Inspect ops/consolidate mutation policy (ruleset, rule).",
        discussion: """
            A ruleset is opt-in — selected via --ruleset or LLMEMORY_RULESET.
            Rules carry constraints (ops.whitelist, ops.deny, ...) bound to
            an axis via params.axis. The ops gate computes effective policy
            per op axis and enforces it.

            SEE ALSO
                ruleset list, ruleset show, ruleset effective
            """,
        subcommands: [RulesetList.self, RulesetShow.self, RulesetEffective.self]
    )
    
    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}

struct RulesetList: AsyncParsableCommand {
    struct Output: Encodable {
        enum CodingKeys: String, CodingKey {
            case id, name, description
            case ruleCount = "rule_count"
        }
        
        // MARK: - Property
        let id: String
        let name: String
        let description: String?
        let ruleCount: Int
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    // MARK: - Property
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List rulesets with rule counts.",
        discussion: """
            EXAMPLES
                llmemory ruleset list --home brain
            """
    )
    
    @OptionGroup var global: GlobalHomeOptions
    @OptionGroup var format: OutputFormat
    
    // MARK: - Initializer
    // MARK: - Public
    func run() async throws {
        let items = try await RulesetFeature.list(home: global.home).map { summary in
            Output(
                id: summary.id,
                name: summary.name,
                description: summary.description,
                ruleCount: summary.ruleCount
            )
        }
        
        render(items, json: format.json) { rulesets in
            [
                .table(
                    rulesets.map { ruleset in
                        [
                            ruleset.id,
                            String(ruleset.ruleCount),
                            ruleset.description ?? ruleset.name
                        ]
                    },
                    headers: ["id", "rules", "description"]
                )
            ]
        }
    }
    
    // MARK: - Private
}

struct RulesetShow: AsyncParsableCommand {
    struct RuleOutput: Encodable {
        // MARK: - Property
        let id: Int64
        let kind: String
        let params: String
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    struct Output: Encodable {
        // MARK: - Property
        let id: String
        let name: String
        let description: String?
        let rules: [RuleOutput]
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    // MARK: - Property
    static let configuration = CommandConfiguration(
        commandName: "show",
        abstract: "Show a ruleset's rules.",
        discussion: """
            EXAMPLES
                llmemory ruleset show response --home brain
            """
    )
    
    @Argument(help: ArgumentHelp("Ruleset id to inspect.", valueName: "id"))
    var id: String
    
    @OptionGroup var global: GlobalHomeOptions
    @OptionGroup var format: OutputFormat
    
    // MARK: - Initializer
    // MARK: - Public
    func run() async throws {
        let output: Output? = try await RulesetFeature.show(home: global.home, id: id).map { ruleset in
            Output(
                id: ruleset.id,
                name: ruleset.name,
                description: ruleset.description,
                rules: ruleset.rules.map { rule in
                    RuleOutput(id: rule.id, kind: rule.kind, params: rule.paramsJSON)
                }
            )
        }
        
        guard let result = output else {
            FileHandle.standardError.write(
                "ruleset not found: \(id)\n".data(using: .utf8) ?? Data()
            )
            
            throw ExitCode.failure
        }
        
        render(result, json: format.json) { ruleset in
            var pairs = [("id", ruleset.id), ("name", ruleset.name)]
            
            if let description = ruleset.description {
                pairs.append(("description", description))
            }
            
            return [
                .keyValue(pairs),
                .section("rules (\(ruleset.rules.count))"),
                .table(
                    ruleset.rules.map { rule in [String(rule.id), rule.kind, rule.params] },
                    headers: ["id", "kind", "params"]
                )
            ]
        }
    }
    
    // MARK: - Private
}

struct RulesetEffective: AsyncParsableCommand {
    // MARK: - Property
    static let configuration = CommandConfiguration(
        commandName: "effective",
        abstract: "Resolve effective policy of a ruleset for an axis.",
        discussion: """
            Combines rules in <ruleset> matching <axis> (rule.params.axis
            equals axis or '*') into a single policy.

            COMBINATION
                ops.whitelist             AND (intersection)
                ops.deny                  OR  (union)
                consolidate.mode          most conservative wins
                archive/merge/stale.auto  false if any rule says false

            EXAMPLES
                llmemory ruleset effective response skill --home brain
            """
    )
    
    @Argument(help: ArgumentHelp("Ruleset id to inspect (positional; the --ruleset mutation-gate (on ops apply etc.) is unrelated and ignored here).", valueName: "id"))
    var ruleset: String
    
    @Argument(help: ArgumentHelp("Axis name (e.g. `skill`, `spec`). Use `*` to see axis-agnostic rules only.", valueName: "axis"))
    var axis: String
    
    @OptionGroup var global: GlobalHomeOptions
    @OptionGroup var format: OutputFormat
    
    // MARK: - Initializer
    // MARK: - Public
    func run() async throws {
        guard let effective = try await RulesetFeature.effective(
            home: global.home,
            ruleset: ruleset,
            axis: axis
        ) else {
            FileHandle.standardError.write(
                "ruleset not found: \(ruleset)\n".data(using: .utf8) ?? Data()
            )
            
            throw ExitCode.failure
        }
        
        renderReflected(effective, json: format.json)
    }
    
    // MARK: - Private
}
