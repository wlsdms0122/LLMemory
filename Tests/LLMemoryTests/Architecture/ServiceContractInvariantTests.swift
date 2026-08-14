//
//  ServiceContractInvariantTests.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/15/26.
//

import Testing
import Foundation

// Services are named by contract, never by implementation. Every service has
// a `XServiceable` protocol, every reference is `any XServiceable`, and the
// one place a concrete service type is spelled at all is the composition
// root that constructs it.
//
// The point is not ceremony: a call site that names the implementation can
// reach past the contract into whatever else that type happens to expose,
// and every such reach is a dependency nobody declared.
@Suite("ServiceContract Invariant Tests")
struct ServiceContractInvariantTests {
    // MARK: - Property
    private let source = PackageSource()
    private let sources: [SwiftSourceFile]

    // MARK: - Initializer
    init() {
        sources = source.files(in: "Sources").map(SwiftSourceFile.init)
    }

    // MARK: - Test
    @Test("every service declares a contract and conforms to it")
    func everyServiceHasAContract() {
        // Given
        #expect(!sources.isEmpty, "no sources found under \(source.root.path)")

        let services = sources
            .filter { file in file.name.hasSuffix("Service.swift") }
            .map { file in String(file.name.dropLast(".swift".count)) }

        #expect(!services.isEmpty, "no service implementations found")

        // When
        let contracts = Set(
            sources
                .filter { file in file.name.hasSuffix("Serviceable.swift") }
                .map { file in String(file.name.dropLast(".swift".count)) }
        )
        let missing = services.filter { service in !contracts.contains("\(service)able") }
        let unconformed = sources
            .filter { file in services.contains(String(file.name.dropLast(".swift".count))) }
            .filter { file in
                let service = String(file.name.dropLast(".swift".count))

                return !file.codeLines().contains { _, text in
                    text.contains("struct \(service): \(service)able")
                }
            }
            .map(\.name)

        // Then
        #expect(missing.isEmpty, """
            service without a contract — the protocol is the type the rest of \
            the package is allowed to know:
            \(missing.joined(separator: "\n"))
            """)
        #expect(unconformed.isEmpty, """
            service that does not declare its own contract — a protocol nothing \
            conforms to is documentation, not a contract:
            \(unconformed.joined(separator: "\n"))
            """)
    }

    @Test("a concrete service type is named only where it is constructed")
    func serviceTypeNamedOnlyInContainer() {
        // Given
        #expect(!sources.isEmpty, "no sources found under \(source.root.path)")

        // When
        // `\w+Service` with a trailing word boundary — `RetrievalServiceable`
        // does not match, so the contract may be named anywhere. What this
        // covers is the service tier by name; `OperationsEngine` is a service
        // collaborator that is not yet under a contract of its own, and it
        // belongs in this pattern the moment it has one.
        //
        // The exemption is per file and is exactly one token — the type that
        // file declares. A file may admit what it is; it may not name a
        // sibling. Exempting `*Service.swift` wholesale would leave
        // `NotesService.swift` free to hold `let retrieval: RetrievalService`
        // again, which is the shape this contract layer exists to remove.
        let concrete = try! NSRegularExpression(pattern: #"\b\w+Service\b"#)
        let compositionRoot = "Sources/LLMemory/Feature/Container.swift"
        let violations = sources
            .filter { file in !file.url.path.hasSuffix(compositionRoot) }
            .flatMap { file in
                let own = String(file.name.dropLast(".swift".count))

                return file.codeLines().flatMap { number, text -> [String] in
                    concrete
                        .matches(in: text, range: NSRange(text.startIndex..., in: text))
                        .compactMap { match in Range(match.range, in: text).map { String(text[$0]) } }
                        .filter { name in name != own }
                        .map { name in "\(file.location(number))  [\(name)]" }
                }
            }

        // Then
        #expect(violations.isEmpty, """
            concrete service type outside the composition root — collaborators \
            are declared and injected as `any XServiceable`; naming the \
            implementation is how a call site acquires an undeclared dependency:
            \(violations.joined(separator: "\n"))
            """)
    }
}
