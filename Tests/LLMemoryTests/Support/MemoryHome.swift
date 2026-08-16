//
//  MemoryHome.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import GRDB
@testable import LLMemory

final class MemoryHome: BrainHome, @unchecked Sendable {
    // MARK: - Property
    // One fixture at a time. Brains no longer share process state — each home
    // owns its paths, caches and connection — but the fixtures still share a
    // temporary directory tree and the flock beneath it, so serialising them
    // keeps a test that throws half-way from stranding another one.
    private static let exclusion = NSLock()
    
    let url: URL
    // One clock reading per fixture. Tests that each called their own Date() could straddle a second
    // boundary and compare timestamps that were never meant to differ.
    let now: Int
    let session: Session

    // What a transaction is handed when a test runs one directly instead of
    // through a scope.
    var brain: BrainContext { session.context }

    var paths: Paths { session.context.paths }

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
        
        Self.exclusion.lock()
        
        do {
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
        } catch {
            Self.exclusion.unlock()
            
            throw error
        }
    }
    
    deinit {
        try? FileManager.default.removeItem(at: url)
        
        session.storage.disconnect()
        
        session.context.config.discardCache(genes: session.context.genes)
        
        Self.exclusion.unlock()
    }
    
    // MARK: - Public
    // MARK: - Private
}
