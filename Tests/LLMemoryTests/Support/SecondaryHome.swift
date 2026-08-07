//
//  SecondaryHome.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/8/26.
//

import Foundation

// A second state root, for the tests whose subject is moving the process from one home to another.
// It deliberately does not take MemoryHome's exclusion lock and does not reset the global connection:
// rebinding is exactly the thing that lock forbids everyone else from doing, and a test that verifies
// rebinding has to be allowed to do it. It never binds itself — the test drives Session.configure.
final class SecondaryHome: BrainHome {
    // MARK: - Property
    let url: URL
    let now: Int
    
    // MARK: - Initializer
    init(prefix: String = "llmemory-test-secondary") throws {
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
    }
    
    deinit {
        try? FileManager.default.removeItem(at: url)
    }
    
    // MARK: - Public
    // MARK: - Private
}
