//
//  GlobalHomeOptions.swift
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

    // The session this invocation belongs to, resolved here and nowhere else.
    // The flag wins; otherwise the runtime's ambient MEMORY_SESSION_ID answers.
    // Below this line it is a value that was already decided — a service that
    // re-derived it would be a second answer to the same question.
    var session: String? {
        if !sessionId.isEmpty { return sessionId }

        let ambient = ProcessInfo.processInfo.environment["MEMORY_SESSION_ID"]

        return (ambient?.isEmpty ?? true) ? nil : ambient
    }

    // MARK: - Initializer
    // MARK: - Public
    func validate() throws {
        if home.isEmpty {
            throw ValidationError("--home <path> required (place after the leaf subcommand)")
        }
    }
    
    // MARK: - Private
}
