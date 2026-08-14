//
//  QueryLint.swift
//  LLMemoryCLI
//
//  Created by JSilver on 8/15/26.
//

import ArgumentParser
import Foundation
import LLMemory

struct QueryLint: AsyncParsableCommand {
    // MARK: - Property
    static let configuration = CommandConfiguration(
        commandName: "lint",
        abstract: "Rule-based consistency check (frontmatter, tag policy, links).",
        discussion: """
            Deterministic checks only — reports facts, never decides. Two severities:
            `error` = invariant violations (integrity gate), `warn` = quality facts
            (improvement queue). Slice by --severity / --code / --limit so each consumer
            pulls only its rows.

            A warn is a judgment request. Once reviewed and kept, close it with
            `dismiss_candidate kind="lint:<code>"` and it stops re-surfacing until the note's
            shape diverges or a corpus reorg reopens it — otherwise the same finding is
            re-litigated every cycle. `--include-dismissed` shows the suppressed ones.
            Errors are never dismissible or suppressed.

            `subject` is what the finding is about, and `target_scope` (json) says which kind:
            `note` = a note id (dismiss with `id`), `corpus` = a fact no note owns, such as
            a tag pair (dismiss with `target`, and only a corpus reorg reopens it).

            EXIT STATUS
                0   no errors in the returned set
                1   one or more errors in the returned set

            EXAMPLES
                llmemory query lint --home brain
                llmemory query lint --severity error --home brain        # integrity gate
                llmemory query lint --code enrich-thin --limit 10 --home brain
                llmemory query lint --id principles --home brain
                llmemory query lint --rules --home brain                 # rule catalog
                llmemory query lint --include-dismissed --home brain     # incl. kept warns
            """
    )
    
    @OptionGroup var global: GlobalHomeOptions
    @OptionGroup var format: OutputFormat
    
    @Option(name: .long, help: "Lint only this note (default: all).")
    var id: String?
    
    @Option(name: .long, help: "Only this issue code (e.g. enrich-thin).")
    var code: String?
    
    @Option(name: .long, help: "Only this severity (error|warn).")
    var severity: String?
    
    @Option(name: .long, help: "Cap rows returned (default: no cap).")
    var limit: Int?
    
    @Flag(name: .long, help: "List registered rules (code, severity, scope) instead of linting.")
    var rules: Bool = false
    
    @Flag(name: .long, help: "Include warns closed by dismiss_candidate.")
    var includeDismissed: Bool = false
    
    // MARK: - Initializer
    // MARK: - Public
    func run() async throws {
        let brain = Brain(home: global.home)
        
        if rules {
            let catalog = brain.query.lintRuleCatalog()
            
            CommandOutput().render(catalog, json: format.json) { rules in
                [
                    .table(
                        rules.map { rule in [rule.severity, rule.code, rule.scope] },
                        headers: ["sev", "code", "scope"]
                    )
                ]
            }
            
            return
        }
        
        let issues = try await brain.query.lint(
            id: id,
            code: code,
            severity: severity,
            limit: limit,
            includeDismissed: includeDismissed
        )
        
        CommandOutput().render(issues, json: format.json) { issues in
            [
                .table(
                    issues.map { issue in
                        [issue.severity, issue.target.subject, issue.code, issue.message]
                    },
                    headers: ["sev", "subject", "code", "message"]
                )
            ]
        }
        
        if issues.contains(where: { issue in issue.severity == "error" }) {
            throw ExitCode(1)
        }
    }
    
    // MARK: - Private
}
