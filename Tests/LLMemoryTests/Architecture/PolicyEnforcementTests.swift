//
//  PolicyEnforcementTests.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/8/26.
//

import Testing
import Foundation
@testable import LLMemory

@Suite("PolicyEnforcement Tests")
struct PolicyEnforcementTests {
    // MARK: - Property
    // The predicates that decide whether a note is visible, decayable or exempt. Spelled out in a
    // query rather than composed from Policy, they drift apart one query at a time.
    private static let forbidden = try! NSRegularExpression(pattern: [
        #"archived = [01]"#,
        #"template IS NULL"#,
        #"COALESCE\([A-Za-z]*\.?stale, ?0\) = [01]"#,
        #"priority ?(!=|=|<>) ?'(eager|lazy)'"#,
        #"priority (NOT )?IN ?\('(eager|lazy)'\)"#,
        #"\blocked = [01]"#,
        #"NOT EXISTS ?\(SELECT 1 FROM candidate_dismissals"#
    ].joined(separator: "|"))
    
    private let source = PackageSource()
    
    // MARK: - Initializer
    // MARK: - Test
    @Test("gate predicates are written once in Policy and composed everywhere else")
    func gatePredicatesLiveOnlyInPolicy() {
        // Given
        let sources = source.files(in: "Sources/LLMemory")
        
        #expect(!sources.isEmpty, "no LLMemory sources found under \(source.root.path)")
        
        // When
        let violations = sources
            .filter { url in url.lastPathComponent != "Policy.swift" }
            .map(SwiftSourceFile.init)
            .flatMap { file in Self.rawPredicates(in: file) }
        
        // Then
        #expect(violations.isEmpty, """
            Raw gate predicate outside Policy.swift — compose Policy atoms instead \
            (Policy.surface / decayCandidate / live / fresh / forgetExempt / …):
            \(violations.joined(separator: "\n"))
            """)
    }
    
    // MARK: - Private
    private static func rawPredicates(in file: SwiftSourceFile) -> [String] {
        file.codeLines()
            // An UPDATE assigns these columns rather than gating on them — that is a write, not a gate.
            .filter { _, text in !text.contains(" SET ") }
            .filter { _, text in
                let scanned = text as NSString
                
                return forbidden.firstMatch(
                    in: text,
                    range: NSRange(location: 0, length: scanned.length)
                ) != nil
            }
            .map { number, text in
                "\(file.location(number))  \(text.trimmingCharacters(in: .whitespaces))"
            }
    }
}
