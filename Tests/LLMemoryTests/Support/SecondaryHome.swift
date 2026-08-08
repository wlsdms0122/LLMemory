//
//  SecondaryHome.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/8/26.
//

import Foundation
@testable import LLMemory

// A second state root, for the tests whose subject is running two sessions in one process.
// It deliberately does not take MemoryHome's exclusion lock: coexistence is exactly the thing
// that lock forbids everyone else from doing, and a test that verifies it has to be allowed to.
// Constructing its Session moves the process-global Paths remnant — the test restores it.
final class SecondaryHome: BrainHome {
    // MARK: - Property
    let url: URL
    let now: Int
    let session: Session
    
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
        
        session = Session(home: url.path)
    }
    
    deinit {
        try? FileManager.default.removeItem(at: url)
    }
    
    // MARK: - Public
    // MARK: - Private
}
