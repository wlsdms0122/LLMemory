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

    @Test("scopes are opened by services only")
    func scopeDispatchStaysInService() {
        // When
        let violations = sources
            .filter { file in !file.url.path.contains("/LLMemory/Service/") }
            .flatMap { file in
                file.codeLines()
                    .filter { _, text in
                        text.contains("storage.run(") || text.contains("storage.run {")
                            || text.contains("storage.read(") || text.contains("storage.read {")
                    }
                    .map { number, _ in file.location(number) }
            }

        // Then
        #expect(violations.isEmpty, """
            storage.run/read outside the service tier — surfaces call a domain \
            service, which is the one tier that opens scopes:
            \(violations.joined(separator: "\n"))
            """)
    }

    @Test("a transaction body is entered directly only inside Module/DB")
    func performStaysInDBModule() {
        // When — Config warming and Session-driven seeding are lifecycle code
        // that already holds a db handle under the sync gate.
        let allowed = ["Config.swift", "Seeding.swift"]
        let violations = sources
            .filter { file in !file.url.path.contains("/LLMemory/Module/DB/") }
            .filter { file in !allowed.contains(file.url.lastPathComponent) }
            .flatMap { file in
                file.codeLines()
                    .filter { _, text in text.contains(".perform(") }
                    .map { number, _ in file.location(number) }
            }

        // Then
        #expect(violations.isEmpty, """
            transaction.perform outside Module/DB — services and the engine go \
            through scope.run; direct perform is transaction-to-transaction \
            composition inside the DB module only:
            \(violations.joined(separator: "\n"))
            """)
    }

    @Test("a scope is constructed by storage alone")
    func scopeConstructionStaysInStorage() {
        // When
        // Constructor *calls* only — a type annotation never carries an open
        // paren right after the name, so any `GRDBScope(` / `GRDBReadScope(`
        // is a construction, including one whose argument wraps to the next
        // line.
        let construction = try! NSRegularExpression(pattern: #"GRDB(Read)?Scope\("#)
        let allowed = ["GRDBStorage.swift", "GRDBScope.swift"]
        let violations = sources
            .filter { file in !allowed.contains(file.url.lastPathComponent) }
            .flatMap { file in
                file.codeLines()
                    .filter { _, text in
                        construction.firstMatch(
                            in: text,
                            range: NSRange(text.startIndex..., in: text)
                        ) != nil
                    }
                    .map { number, _ in file.location(number) }
            }

        // Then
        #expect(violations.isEmpty, """
            GRDBScope constructed outside storage — a scope exists only inside \
            storage.run/read, which owns the rollback boundary:
            \(violations.joined(separator: "\n"))
            """)
    }

    @Test("services are assembled by the container alone")
    func serviceConstructionStaysInContainer() {
        // When
        // Constructor calls only — `XxxService(` with an open paren is a
        // construction; type references (return types, nested types) never
        // carry one. The engine counts too: it is a service collaborator,
        // not a global.
        let construction = try! NSRegularExpression(
            pattern: #"\b\w+Service\(|\bOperationsEngine\("#
        )
        let allowed = ["Services.swift"]
        let violations = sources
            .filter { file in !allowed.contains(file.url.lastPathComponent) }
            .flatMap { file in
                file.codeLines()
                    .filter { _, text in
                        construction.firstMatch(
                            in: text,
                            range: NSRange(text.startIndex..., in: text)
                        ) != nil
                    }
                    .map { number, _ in file.location(number) }
            }

        // Then
        #expect(violations.isEmpty, """
            service constructed outside the container — instances are wired \
            once at the composition root and injected; nothing assembles its \
            own collaborator:
            \(violations.joined(separator: "\n"))
            """)
    }

    @Test("the storage gates (connect/writeLock) have named owners only")
    func storageGatesStayInModule() {
        // When
        let allowed = ["GRDBStorage.swift", "Session.swift", "Config.swift"]
        let violations = sources
            .filter { file in !allowed.contains(file.url.lastPathComponent) }
            .flatMap { file in
                file.codeLines()
                    .filter { _, text in
                        text.contains(".writeLock") || text.contains("storage.connect()")
                    }
                    .map { number, _ in file.location(number) }
            }

        // Then
        #expect(violations.isEmpty, """
            Direct storage gate outside its owners — storage defines the gates, \
            Session.bootstrap (lifecycle) and Config warming are the only users:
            \(violations.joined(separator: "\n"))
            """)
    }
}
