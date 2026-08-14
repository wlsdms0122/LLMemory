//
//  IndexCommand.swift
//  LLMemoryCLI
//
//  Created by JSilver on 8/7/26.
//

import ArgumentParser
import Foundation
import LLMemory

struct IndexCommand: ParsableCommand {
    // MARK: - Property
    static let configuration = CommandConfiguration(
        commandName: "index",
        abstract: "Maintain the derived index — derive (build/vector) + verify.",
        discussion: """
            memory.db is a derived projection of the cortex/ markdown (SSoT).
            This group builds that projection and verifies it stays faithful.
              
              DERIVE   build   full/incremental cortex→DB sync (--path for one note)
                       vector  rebuild the algorithmic note-vector layer
              VERIFY   verify  integrity / sources / terms (see `index verify`)
            
            EXAMPLES
                llmemory index build --home brain
                llmemory index verify integrity --level 2 --home brain
            
            SEE ALSO
                index build, index verify
            """,
        subcommands: [IndexBuild.self, IndexVectors.self, IndexVerify.self]
    )
    
    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}
