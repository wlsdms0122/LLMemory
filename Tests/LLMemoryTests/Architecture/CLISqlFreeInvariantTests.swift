//
//  CLISqlFreeInvariantTests.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/8/26.
//

import Testing
import Foundation

@Suite("CLISqlFreeInvariant Tests")
struct CLISqlFreeInvariantTests {
    // MARK: - Property
    private static let forbidden = [
        "sql:", "Row.fetch", "Int.fetch", "String.fetch", "db.execute(", "StatementArguments("
    ]
    
    private let source = PackageSource()
    // Recursive — the CLI keeps most of its code in Command/ and Support/, so a shallow listing would
    // let this guard pass while reading a single file.
    private let sources: [SwiftSourceFile]
    
    // MARK: - Initializer
    init() {
        sources = source.files(in: "Sources/LLMemoryCLI").map(SwiftSourceFile.init)
    }
    
    // MARK: - Test
    @Test("the CLI holds no SQL — queries belong to a service the command calls")
    func cliSourceContainsNoRawSQL() {
        // Given
        #expect(!sources.isEmpty, "no CLI sources found under \(source.root.path)")
        
        // When
        let violations = sources.flatMap { file in
            file.codeLines().flatMap { number, text -> [String] in
                Self.forbidden
                    .filter { pattern in text.contains(pattern) }
                    .map { pattern in
                        "\(file.location(number))  [\(pattern)]  \(text.trimmingCharacters(in: .whitespaces))"
                    }
            }
        }
        
        // Then
        #expect(violations.isEmpty, """
            CLI must be SQL-free — move these queries into an LLMemory service (e.g. Reads) and call \
            it from the command:
            \(violations.joined(separator: "\n"))
            """)
    }
    
    @Test("the CLI does not import GRDB — a command that can reach the driver will eventually use it")
    func cliDoesNotImportGRDB() {
        // Given
        #expect(!sources.isEmpty, "no CLI sources found under \(source.root.path)")
        
        // When
        let offenders = sources
            .filter { file in
                file.lines().contains { _, text in
                    text.trimmingCharacters(in: .whitespaces) == "import GRDB"
                }
            }
            .map(\.name)
        
        // Then
        #expect(offenders.isEmpty, """
            CLI must not import GRDB — database access belongs in a Feature function. Offending \
            files: \(offenders.joined(separator: ", "))
            """)
    }
}
