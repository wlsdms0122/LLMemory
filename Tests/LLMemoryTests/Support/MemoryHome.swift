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

            // A fresh install owns zero axes, but most tests model a brain that has lived for a
            // while. Pre-creating the vocabulary the fixtures rely on keeps every inline op from
            // having to carry an axis_description.
            try session.storage.connect().write { database in
                for axis in ["flow", "tech", "persona", "repo", "env", "journal"] {
                    try EnsureAxisTransaction(axis: axis, description: "(test axis)", now: now).perform(database)
                }
            }
            
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
