//
//  MemoryHome.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import GRDB
@testable import LLMemory

// One brain in a temporary directory, torn down with the test. Nothing is
// shared between two of them — paths, caches and the connection all belong to
// the Session — so tests that each build one do not have to take turns.
final class MemoryHome: BrainHome, @unchecked Sendable {
    // MARK: - Property
    let url: URL
    // One clock reading per fixture. Tests that each called their own Date() could straddle a second
    // boundary and compare timestamps that were never meant to differ.
    let now: Int
    let session: Session

    // What a transaction is handed when a test runs one directly instead of
    // through a scope.
    var brain: BrainContext { session.context }

    var layout: BrainLayout { session.context.layout }

    var genes: Genes { session.context.genes }

    var config: Config { session.context.config }
    
    // The window init/update plant inside, so a test can exercise seeding the way
    // the commands do rather than a shape only tests can produce.
    func bootstrapScope() throws -> BootstrapScope {
        BootstrapScope(queue: try session.storage.connect(), context: session.context)
    }

    // MARK: - Initializer
    init(prefix: String = "llmemory-test") throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)")
        now = Int(Date().timeIntervalSince1970)
        
        let fileManager = FileManager.default

        try fileManager.createDirectory(
            at: url.appendingPathComponent("data"),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: url.appendingPathComponent("cortex"),
            withIntermediateDirectories: true
        )

        session = Session(home: url.path)

        try session.storage.initialize()

        _ = try session.storage.connect()

        // The Session warmed against a database that did not exist yet.
        session.rewarm()
    }
    
    deinit {
        try? FileManager.default.removeItem(at: url)
        
        session.storage.disconnect()
    }
    
    // MARK: - Public
    // MARK: - Private
}
