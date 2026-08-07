//
//  RequiredFieldLiteralTests.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/8/26.
//

import Testing
import Foundation

@Suite("RequiredFieldLiteral Tests")
struct RequiredFieldLiteralTests {
    // MARK: - Property
    // Dispatch already enforces the schema's requiredNames(given:). A handler that checks again holds
    // a second copy of the rule, and second copies drift.
    private static let owners = ["Handlers.swift", "Transaction.swift"]
    
    private let source = PackageSource()
    
    // MARK: - Initializer
    // MARK: - Test
    @Test("no handler restates its required fields — the schema is the only declaration")
    func noHandRolledRequiredLiteralsInValidates() {
        // Given
        let sources = source.files(in: "Sources/LLMemory").map(SwiftSourceFile.init)
        
        #expect(!sources.isEmpty, "no LLMemory sources found under \(source.root.path)")
        
        // When
        let violations = sources
            .filter { file in !Self.owners.contains(file.name) }
            .flatMap { file in
                file.codeLines()
                    .filter { _, text in text.contains("checkRequired(") }
                    .map { number, _ in file.location(number) }
            }
        
        // Then
        #expect(violations.isEmpty, """
            per-handler required-field literal — declare it in the OpSchema instead, dispatch \
            enforces requiredNames(given:): \(violations.joined(separator: ", "))
            """)
    }
}
