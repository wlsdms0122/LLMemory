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
    @Test("Transaction.apply has no internal caller — an automatic path must surface its status")
    func transactionApplyHasNoInternalCallers() {
        // Given
        let sources = source.files(in: "Sources")
        
        #expect(!sources.isEmpty, "no sources found under \(source.root.path)")
        
        // When
        let violations = sources
            .filter { url in !Self.isOwner(url) }
            .flatMap { url in Self.callSites(of: "Transaction.apply", in: url) }
        
        // Then
        #expect(violations.isEmpty, """
            Internal Transaction.apply consumer — an automatic path must surface Result.status \
            fail-loud rather than swallow it:
            \(violations.joined(separator: "\n"))
            """)
    }
    
    // MARK: - Private
    // The ops feature and the ops command are the transaction's own surface — they are where apply is
    // supposed to be called from.
    private static func isOwner(_ url: URL) -> Bool {
        url.path.contains("/Feature/Ops/") || url.path.hasSuffix("Command/Ops.swift")
    }
    
    private static func callSites(of symbol: String, in url: URL) -> [String] {
        let file = SwiftSourceFile(url)
        
        return file.codeLines()
            .filter { _, text in text.contains(symbol) }
            .map { number, _ in file.location(number) }
    }
}
