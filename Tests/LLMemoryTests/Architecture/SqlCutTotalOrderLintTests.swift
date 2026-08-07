//
//  SqlCutTotalOrderLintTests.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import Testing

@Suite("SqlCutTotalOrderLint Tests")
struct SqlCutTotalOrderLintTests {
    // MARK: - Property
    private let source = PackageSource()
    private let rule = SqlCutRule()
    
    // MARK: - Initializer
    // MARK: - Test
    @Test("every LIMIT cut orders on a unique column, so the same query keeps the same answer")
    func everyLimitCutNamesATiebreak() throws {
        // Given
        let sources = source.files(in: "Sources")
        
        #expect(!sources.isEmpty, "no sources found under \(source.root.path)")
        
        // When
        var violations: [SqlCutViolation] = []
        
        for url in sources {
            let text = try String(contentsOf: url, encoding: .utf8)
            
            guard text.contains("LIMIT") else { continue }
            
            let relativePath = url.path.replacingOccurrences(of: source.root.path + "/", with: "")
            
            for (body, line) in SwiftStringLiterals(text).bodies() {
                if let violation = rule.violation(body: body, file: relativePath, line: line) {
                    violations.append(violation)
                }
            }
        }
        
        // Then
        #expect(violations.isEmpty, """
            LIMIT cut with no total order — the row that survives the cut is whichever one SQLite \
            happened to reach first:
            \(violations.map { violation in "  \(violation)" }.joined(separator: "\n"))
            """)
    }
}
