//
//  LLMemoryCLI.swift
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
            and cortex/ note files (an id `a.b.c` is the file a/b/c.md). All file and DB mutations go
            through `operations apply` — no API for direct edits.
            
            GLOBAL OPTIONS
                Accepted by every leaf subcommand; place AFTER the subcommand.
                    --home <state-root>   Required. Path to brain home.
                    --session-id <id>     Override MEMORY_SESSION_ID for this call.
                
                ok:   llmemory query search foo --home brain
                bad:  llmemory --home brain query search foo
            
            STATE LAYOUT
                data/memory.db          catalog, FTS5 index, events
                cortex/**/*.md          note files (markdown SSoT; path = id)
                cortex/.trash/          soft-deleted notes
            
            ENVIRONMENT
                MEMORY_SESSION_ID            Default for --session-id.
            
            OUTPUT
                JSON on stdout, one line per command, unless noted.
            
            SEE ALSO
                operations apply, operations vocab
            """,
        subcommands: [
            InitCommand.self,
            UpdateCommand.self,
            QueryCommand.self,
            OperationsCommand.self,
            IndexCommand.self,
            ConsolidateCommand.self,
            GenomeCommand.self
        ]
    )
    
    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}
