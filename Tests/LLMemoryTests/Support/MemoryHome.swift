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
    // LLMemory keeps its state root, database queue and config cache in process-wide storage, so two
    // live homes would silently share one database. Holding the lock for the fixture's lifetime makes
    // "one at a time" structural instead of a rule every test has to remember, and releasing it from
    // deinit means a test that throws half-way cannot strand the lock and hang the whole run.
    private static let exclusion = NSLock()
    
    let url: URL
    // One clock reading per fixture. Tests that each called their own Date() could straddle a second
    // boundary and compare timestamps that were never meant to differ.
    let now: Int
    let session: Session
    
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
        
        Config.invalidateCache()
        
        Self.exclusion.unlock()
    }
    
    // MARK: - Public
    // MARK: - Private
}
