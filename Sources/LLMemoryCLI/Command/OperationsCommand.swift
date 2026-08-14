//
//  OperationsCommand.swift
//  LLMemoryCLI
//
//  Created by JSilver on 8/7/26.
//

import ArgumentParser
import Foundation
import LLMemory

struct OperationsCommand: ParsableCommand {
    // MARK: - Property
    static let configuration = CommandConfiguration(
        commandName: "operations",
        abstract: "Atomic write transactions — all mutations go through here.",
        discussion: """
            All file and DB writes go through `apply`. Each transaction validates
            every op, snapshots affected files, applies inside a single SAVEPOINT,
            and rolls back DB and files on any failure. No direct file or row edits.
            
            The canonical spelling is `operations`; `ops` reaches the same
            group as an alias.
            
            SEE ALSO
                operations apply, operations vocab, operations describe
            """,
        subcommands: [OperationsApply.self, OperationsDryRun.self, OperationsVocab.self, OperationsDescribe.self],
        // Owner call: the surface may stay short — `ops` aliases the
        // spelled-out internal name, and both forms reach the same command.
        aliases: ["ops"]
    )
    
    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}
