//
//  IndexVerify.swift
//  LLMemoryCLI
//
//  Created by JSilver on 8/15/26.
//

import ArgumentParser
import Foundation
import LLMemory

struct IndexVerify: ParsableCommand {
    // MARK: - Property
    static let configuration = CommandConfiguration(
        commandName: "verify",
        abstract: "Verify the derived index — integrity, source drift, enrichment terms.",
        discussion: """
            Three facets of one question — is the index still valid?

                integrity   schema/row/FTS/semantic invariants (read-only)
                sources     source-file drift → source_stale (a write)
                terms       promote/reject pending retrieval terms (a write)

            SEE ALSO
                index verify integrity, index verify sources, index verify terms
            """,
        subcommands: [IndexVerifyIntegrity.self, IndexVerifySources.self, IndexVerifyTerms.self]
    )
    
    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}
