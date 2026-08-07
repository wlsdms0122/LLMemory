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
    private static let writeEntry = try! NSRegularExpression(pattern: #"(\b\w+)\.write\s*\{"#)
    
    private let source = PackageSource()
    
    // MARK: - Initializer
    // MARK: - Test
    @Test("every raw queue write goes through DB.write, which owns the lock and the transaction")
    func rawQueueWritesLiveOnlyInDB() {
        // Given
        let sources = source.files(in: "Sources/LLMemory")
        
        #expect(!sources.isEmpty, "no LLMemory sources found under \(source.root.path)")
        
        // When
        let violations = sources
            .filter { url in url.lastPathComponent != "DB.swift" }
            .flatMap { url in Self.foreignWrites(in: url) }
        
        // Then
        #expect(violations.isEmpty, """
            Raw queue write outside DB.swift — route it through DB.write (flock + transaction), or \
            take a `Database` parameter when the caller is already inside one:
            \(violations.joined(separator: "\n"))
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
                .filter { receiver in receiver != "DB" }
                .map { _ in
                    "\(file.location(number))  \(text.trimmingCharacters(in: .whitespaces))"
                }
        }
    }
}
