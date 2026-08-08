//
//  CLI.swift
//  LLMemoryCLI
//
//  Created by JSilver on 8/7/26.
//

import ArgumentParser
import Foundation
import LLMemory

@main
struct LLMemoryCLI: AsyncParsableCommand {
    // MARK: - Property
    static let configuration = CommandConfiguration(
        commandName: "llmemory",
        abstract: "brain memory CLI — note capture, retrieval, consolidation.",
        discussion: """
            Manages a brain home: data/memory.db (catalog, FTS5 index, events)
            and cortex/<axis>/<id>.md note files. All file and DB mutations go
            through `ops apply` — no API for direct edits.

            GLOBAL OPTIONS
                Accepted by every leaf subcommand; place AFTER the subcommand.
                    --home <state-root>   Required. Path to brain home.
                    --session-id <id>     Override MEMORY_SESSION_ID for this call.

                --ruleset <id> is NOT global — it is carried only by the mutators
                (ops apply, ops dry-run), since it is inert everywhere else.

                ok:   llmemory query search foo --home brain
                bad:  llmemory --home brain query search foo

            STATE LAYOUT
                data/memory.db          catalog, FTS5 index, events
                cortex/<axis>/<id>.md   note files (markdown SSoT)
                cortex/.trash/          soft-deleted notes

            ENVIRONMENT
                MEMORY_SESSION_ID            Default for --session-id.
                LLMEMORY_RULESET             Default for --ruleset.
                LLMEMORY_RULESET_LOCKED=1    --ruleset ignored, env required.

            OUTPUT
                JSON on stdout, one line per command, unless noted.

            SEE ALSO
                ops apply, ops vocab, ruleset list
            """,
        subcommands: [
            InitCommand.self,
            UpdateCommand.self,
            QueryCommand.self,
            OpsCommand.self,
            RulesetCommand.self,
            IndexCommand.self,
            ConsolidateCommand.self,
            GenomeCommand.self
        ]
    )
    
    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}
