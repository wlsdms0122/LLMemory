//
//  OneTypePerFileInvariantTests.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/15/26.
//

import Testing
import Foundation

// One file, one top-level type, named after it. A file holding a dozen types
// is a directory that never got made: nothing tells you where a type lives,
// the diff of an unrelated change lands in the same file, and the file's name
// stops predicting its contents.
//
// `converted` is the areas the rule holds for. It began as a ratchet while the
// package was converted one area at a time, and it is now the whole of
// `Sources` — a new area is covered by being written, not by being listed.
@Suite("OneTypePerFile Invariant Tests")
struct OneTypePerFileInvariantTests {
    // MARK: - Property
    private let converted = ["Sources"]

    private let declaration = try! NSRegularExpression(
        pattern: #"^(?:public |internal |private |fileprivate |final |indirect )*(?:struct|enum|class|actor|protocol) +(\w+)"#
    )

    private let source = PackageSource()
    private let sources: [SwiftSourceFile]

    // MARK: - Initializer
    init() {
        sources = source.files(in: "Sources").map(SwiftSourceFile.init)
    }

    // MARK: - Test
    @Test("every file holds one top-level type, named after the file")
    func everyFileHoldsOneTypeNamedAfterIt() {
        // Given
        #expect(!sources.isEmpty, "no sources found under \(source.root.path)")

        let inScope = sources.filter { file in
            converted.contains { area in file.url.path.contains("/\(area)/") }
        }

        #expect(!inScope.isEmpty, "the converted areas matched no files — check the paths")

        // When
        var violations: [String] = []

        for file in inScope {
            let declared = file.codeLines().compactMap { _, text -> String? in
                guard
                    let match = declaration.firstMatch(
                        in: text,
                        range: NSRange(text.startIndex..., in: text)
                    ),
                    let range = Range(match.range(at: 1), in: text)
                else {
                    return nil
                }

                return String(text[range])
            }
            // A file whose name carries a `+` adds to a type it does not own, so
            // there is no name to match — but it may not declare one either.
            // Skipping the file outright would leave exactly the habit this
            // rule removes a place to hide.
            if file.name.contains("+") {
                if !declared.isEmpty {
                    violations.append("\(file.name)  declares \(declared.joined(separator: ", ")) in an extension file")
                }

                continue
            }

            let expected = String(file.name.dropLast(".swift".count))

            if declared.count != 1 {
                violations.append("\(file.name)  declares \(declared.count): \(declared.joined(separator: ", "))")
                continue
            }

            if declared[0] != expected {
                violations.append("\(file.name)  declares \(declared[0])")
            }
        }

        // Then
        #expect(violations.isEmpty, """
            a converted area has drifted — one top-level type per file, and the \
            file is named after it:
            \(violations.joined(separator: "\n"))
            """)
    }
}
