//
//  TypedOperationErrorInvariantTests.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/15/26.
//

import Testing
import Foundation

// The operations layer refuses with a case, not with a string.
//
// `NSError(domain: "Handlers", code: 1)` carries its meaning where only a
// caller printing it can reach, and its domain outlives the type it was named
// after — this package had thirteen copies pointing at a type that no longer
// existed, one of them with no message at all.
@Suite("TypedOperationError Invariant Tests")
struct TypedOperationErrorInvariantTests {
    // MARK: - Property
    private let source = PackageSource()

    // MARK: - Initializer
    // MARK: - Test
    @Test("an op refuses with an OperationError case, never an untyped NSError")
    func opsLayerThrowsTypedErrors() {
        // Given
        let sources = source.files(in: "Sources/LLMemory/Service/OperationsService")
            .map(SwiftSourceFile.init)

        #expect(!sources.isEmpty, "no operations sources found under \(source.root.path)")

        // When
        let violations = sources.flatMap { file in
            file.codeLines()
                .filter { _, text in text.contains("NSError(domain:") }
                .map { number, _ in file.location(number) }
        }

        // Then
        #expect(violations.isEmpty, """
            untyped error in the operations layer — give the event a case on \
            OperationError, so what is refused can be read rather than printed:
            \(violations.joined(separator: "\n"))
            """)
    }
}
