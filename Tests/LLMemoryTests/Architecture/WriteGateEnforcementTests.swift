//
//  WriteGateEnforcementTests.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/8/26.
//

import Testing
import Foundation
@testable import LLMemory

@Suite("WriteGateEnforcement Tests")
struct WriteGateEnforcementTests {
    // MARK: - Property
    private static let writeEntry = try! NSRegularExpression(pattern: #"((?:\b\w+\.)*\w+)\.write\s*\{"#)

    private let source = PackageSource()

    // MARK: - Initializer
    // MARK: - Test
    @Test("every raw queue write goes through GRDBStorage.write, which owns the lock and the transaction")
    func rawQueueWritesLiveOnlyInStorage() {
        // Given
        let sources = source.files(in: "Sources/LLMemory")

        #expect(!sources.isEmpty, "no LLMemory sources found under \(source.root.path)")

        // When
        let violations = sources
            .filter { url in url.lastPathComponent != "GRDBStorage.swift" }
            .filter { url in !url.pathComponents.contains("Transaction") }
            .flatMap { url in Self.foreignWrites(in: url) }

        // Then
        #expect(violations.isEmpty, """
            Raw queue write outside GRDBStorage.swift or a Transaction directory — route it \
            through GRDBStorage.session.write (flock + transaction), convert the caller to a \
            `GRDBWriteTransaction`, or take a `Database` parameter when the caller is already inside one:
            \(violations.joined(separator: "\n"))
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
    private static func foreignWrites(in url: URL) -> [String] {
        let file = SwiftSourceFile(url)

        return file.codeLines().flatMap { number, text -> [String] in
            let scanned = text as NSString
            let matches = writeEntry.matches(
                in: text,
                range: NSRange(location: 0, length: scanned.length)
            )

            return matches
                .map { match in scanned.substring(with: match.range(at: 1)) }
                .filter { receiver in receiver != "GRDBStorage.session" }
                .map { _ in
                    "\(file.location(number))  \(text.trimmingCharacters(in: .whitespaces))"
                }
        }
    }
}
