//
//  LayeringInvariantTests.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/9/26.
//

import Testing
import Foundation

// Feature → Service → Module, wrapped all the way down: GRDB and raw SQL live
// in the Module tier only, and transactions are dispatched by services alone.
// These scans make the tier boundaries fail loudly instead of eroding quietly.
@Suite("LayeringInvariant Tests")
struct LayeringInvariantTests {
    // MARK: - Property
    private let source = PackageSource()
    private let sources: [SwiftSourceFile]

    // MARK: - Initializer
    init() {
        sources = source.files(in: "Sources").map(SwiftSourceFile.init)
    }

    // MARK: - Test
    @Test("GRDB is imported only inside the Module tier")
    func grdbImportStaysInModule() {
        // Given
        #expect(!sources.isEmpty, "no sources found under \(source.root.path)")

        // When
        let violations = sources
            .filter { file in !file.url.path.contains("/LLMemory/Module/") }
            .filter { file in
                file.codeLines().contains { _, text in
                    text.trimmingCharacters(in: .whitespaces) == "import GRDB"
                }
            }

        // Then
        #expect(violations.isEmpty, """
            GRDB import outside the Module tier — features and services speak in \
            domain methods and transactions, never the driver:
            \(violations.map { file in file.url.lastPathComponent }.joined(separator: "\n"))
            """)
    }

    @Test("raw SQL lives only inside Module/DB")
    func rawSQLStaysInDBModule() {
        // Given
        let forbidden = ["sql:", "db.execute(", "StatementArguments("]

        // When
        let violations = sources
            .filter { file in !file.url.path.contains("/LLMemory/Module/DB/") }
            .flatMap { file in
                file.codeLines().flatMap { number, text -> [String] in
                    forbidden
                        .filter { pattern in text.contains(pattern) }
                        .map { pattern in "\(file.location(number))  [\(pattern)]" }
                }
            }

        // Then
        #expect(violations.isEmpty, """
            String SQL outside Module/DB — queries are the DB module's vocabulary; \
            descend them into a query namespace or transaction:
            \(violations.joined(separator: "\n"))
            """)
    }

    @Test("transactions are dispatched by services only")
    func transactionDispatchStaysInService() {
        // When
        let violations = sources
            .filter { file in !file.url.path.contains("/LLMemory/Service/") }
            .flatMap { file in
                file.codeLines()
                    .filter { _, text in text.contains("storage.run(") }
                    .map { number, _ in file.location(number) }
            }

        // Then
        #expect(violations.isEmpty, """
            storage.run outside the service tier — surfaces call a domain service, \
            which is the one tier that runs transactions:
            \(violations.joined(separator: "\n"))
            """)
    }

    @Test("the storage gates (connect/writeLock) are Module-internal")
    func storageGatesStayInModule() {
        // When
        let violations = sources
            .filter { file in !file.url.path.contains("/LLMemory/Module/") }
            .flatMap { file in
                file.codeLines()
                    .filter { _, text in
                        text.contains(".writeLock") || text.contains("storage.connect()")
                    }
                    .map { number, _ in file.location(number) }
            }

        // Then
        #expect(violations.isEmpty, """
            Direct storage gate outside Module — only the lifecycle boundary \
            (Session.bootstrap) and the DB module may touch connect/writeLock:
            \(violations.joined(separator: "\n"))
            """)
    }
}
