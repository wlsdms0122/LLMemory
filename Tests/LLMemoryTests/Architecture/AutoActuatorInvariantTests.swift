//
//  AutoActuatorInvariantTests.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/8/26.
//

import Testing
import Foundation
@testable import LLMemory

@Suite("AutoActuatorInvariant Tests")
struct AutoActuatorInvariantTests {
    // MARK: - Property
    private let source = PackageSource()
    
    // MARK: - Initializer
    // MARK: - Test
    @Test("OperationsEngine.apply has no internal caller — an automatic path must surface its status")
    func transactionApplyHasNoInternalCallers() {
        // Given
        let sources = source.files(in: "Sources")
        
        #expect(!sources.isEmpty, "no sources found under \(source.root.path)")
        
        // When
        let violations = sources
            .filter { url in !Self.isOwner(url) }
            .flatMap { url in Self.callSites(of: "OperationsEngine.apply", in: url) }
        
        // Then
        #expect(violations.isEmpty, """
            Internal OperationsEngine.apply consumer — an automatic path must surface Result.status \
            fail-loud rather than swallow it:
            \(violations.joined(separator: "\n"))
            """)
    }
    
    // MARK: - Private
    // The engine's own module and the ops transactions are the only entries — every
    // other path goes surface → OperationsService (the one decode door) and sees the status.
    private static func isOwner(_ url: URL) -> Bool {
        url.path.contains("/Service/Operations/")
    }
    
    private static func callSites(of symbol: String, in url: URL) -> [String] {
        let file = SwiftSourceFile(url)
        
        return file.codeLines()
            .filter { _, text in text.contains(symbol) }
            .map { number, _ in file.location(number) }
    }
}
