//
//  QueryCommand.swift
//  LLMemoryCLI
//
//  Created by JSilver on 8/7/26.
//

import ArgumentParser
import Foundation
import LLMemory

struct QueryCommand: ParsableCommand {
    // MARK: - Property
    static let configuration = CommandConfiguration(
        commandName: "query",
        abstract: "Read-only queries — search, fetch, structure, stats.",
        discussion: """
            All queries are LLM-free (algorithmic). For free-form text input,
            prefer `related` — it returns a rich snapshot suitable for capture
            and retrieval agents.

            SEE ALSO
                query related, query search, query get
            """,
        subcommands: [
            QueryRelated.self, QuerySearch.self, QueryGet.self,
            QueryEntity.self, QueryStructure.self, QueryNeighbors.self,
            QueryStats.self, QueryList.self, QueryTree.self,
            QueryHistory.self, QueryLint.self, QueryEnrichment.self,
            QueryTemplate.self
        ]
    )
    
    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}
