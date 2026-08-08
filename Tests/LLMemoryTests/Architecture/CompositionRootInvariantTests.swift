//
//  CompositionRootInvariantTests.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/8/26.
//

import Testing
import Foundation
@testable import LLMemory

// Pure DI leaves no ambient storage to gate writes through — instead the graph
// itself is the invariant: storage is constructed only by Session, Session only
// by Brain, and connection-writing transactions declare the write marker that
// carries the cross-process flock.
@Suite("CompositionRoot Tests")
struct CompositionRootInvariantTests {
    // MARK: - Property
    private let source = PackageSource()

    // MARK: - Initializer
    // MARK: - Test
    @Test("GRDBStorage is constructed only by Session — the state binding owns its storage")
    func storageIsConstructedOnlyBySession() {
        // Given
        let sources = source.files(in: "Sources")

        #expect(!sources.isEmpty, "no sources found under \(source.root.path)")

        // When
        let violations = sources
            .filter { url in url.lastPathComponent != "Session.swift" }
            .filter { url in Self.contains(url, "GRDBStorage(") }

        // Then
        #expect(violations.isEmpty, """
            GRDBStorage constructed outside Session.swift — the composition root owns storage; \
            receive it (or a Session/Brain) instead of building your own:
            \(violations.map { url in url.lastPathComponent }.joined(separator: "\n"))
            """)
    }

    @Test("Session is constructed only by Brain — one composition root, no side doors")
    func sessionIsConstructedOnlyByBrain() {
        // Given
        let sources = source.files(in: "Sources")

        // When
        let violations = sources
            .filter { url in url.lastPathComponent != "Brain.swift" }
            .filter { url in Self.contains(url, "Session(home:") }

        // Then
        #expect(violations.isEmpty, """
            Session constructed outside Brain.swift — production code enters through \
            `Brain(home:)`; thread its session down instead of binding a new one:
            \(violations.map { url in url.lastPathComponent }.joined(separator: "\n"))
            """)
    }

    @Test("a transaction that writes through its connection declares the write marker, which carries the flock")
    func connectionWritesDeclareWriteMarker() {
        // Given
        let transactions = source.files(in: "Sources/LLMemory")
            .filter { url in url.pathComponents.contains("Transaction") }

        // When — connection.write without GRDBWriteTransaction runs outside the cross-process lock.
        let violations = transactions.filter { url in
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return false }

            return text.contains("connection.write") && !text.contains(": GRDBWriteTransaction")
        }

        // Then
        #expect(violations.isEmpty, """
            connection.write in a transaction without the GRDBWriteTransaction marker — the write \
            runs outside the cross-process lock:
            \(violations.map { url in url.lastPathComponent }.joined(separator: "\n"))
            """)
    }

    // MARK: - Private
    private static func contains(_ url: URL, _ needle: String) -> Bool {
        let file = SwiftSourceFile(url)

        return file.codeLines().contains { _, text in text.contains(needle) }
    }
}
