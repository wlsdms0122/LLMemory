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
// The rule is enforced per area rather than package-wide, because the areas
// are converted one at a time. `converted` is a ratchet — an area joins the
// list once it holds, and never leaves. What is absent from the list is not
// exempt; it is not done yet.
@Suite("OneTypePerFile Invariant Tests")
struct OneTypePerFileInvariantTests {
    // MARK: - Property
    private let converted = [
        "Sources/LLMemory/Feature",
        "Sources/LLMemory/Module/DB/Migration",
        "Sources/LLMemory/Module/DB/Model",
        "Sources/LLMemory/Module/Lint",
        "Sources/LLMemory/Service/LintService",
        "Sources/LLMemory/Service/OperationsService"
    ]

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
    @Test("a converted area holds one top-level type per file, named after the file")
    func convertedAreasHoldOneTypePerFile() {
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
