//
//  TierDirectionInvariantTests.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/15/26.
//

import Testing
import Foundation

// Feature → Service → Module, and never the other way. The layering suite
// guards what each tier may *do*; this guards what each tier may *name*, which
// is the direction itself: a Module file that mentions a Service type has
// acquired an upward dependency whether or not it calls anything on it.
//
// The failure this catches is quiet by nature — a field of the wrong type
// still compiles, and reads as something a later change is meant to use.
@Suite("TierDirection Invariant Tests")
struct TierDirectionInvariantTests {
    // MARK: - Property
    private let source = PackageSource()
    private let sources: [SwiftSourceFile]

    // MARK: - Initializer
    init() {
        sources = source.files(in: "Sources").map(SwiftSourceFile.init)
    }

    // MARK: - Test
    @Test("the module tier does not name a type the service tier declares")
    func moduleDoesNotNameServiceTypes() {
        // Given
        #expect(!sources.isEmpty, "no sources found under \(source.root.path)")

        let serviceTypes = Set(
            sources
                .filter { file in file.url.path.contains("/LLMemory/Service/") }
                .map { file in String(file.name.dropLast(".swift".count)) }
                .filter { name in !name.contains("+") }
        )

        #expect(!serviceTypes.isEmpty, "no service types found — check the paths")

        // When
        // Each line is split into identifiers once and intersected with the
        // service names. Matching each name against each line by regex instead
        // costs lines × types and recompiles the pattern every time — a guard
        // that grows superlinearly with the corpus is a guard someone
        // eventually deletes from CI.
        let violations = sources
            .filter { file in file.url.path.contains("/LLMemory/Module/") }
            .flatMap { file in
                file.codeLines().flatMap { number, text -> [String] in
                    let identifiers = Set(
                        text.split(whereSeparator: { character in
                            !character.isLetter && !character.isNumber && character != "_"
                        })
                        .map(String.init)
                    )

                    return identifiers.intersection(serviceTypes)
                        .map { name in "\(file.location(number))  [\(name)]" }
                }
            }

        // Then
        #expect(violations.isEmpty, """
            module-tier file naming a service type — the tier below cannot know \
            the tier above, and a field of the wrong type compiles quietly:
            \(violations.sorted().joined(separator: "\n"))
            """)
    }
}
