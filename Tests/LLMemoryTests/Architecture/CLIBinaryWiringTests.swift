//
//  CLIBinaryWiringTests.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/8/26.
//

import Testing
import Foundation

@Suite("CLIBinaryWiring Tests")
struct CLIBinaryWiringTests {
    // MARK: - Property
    private let source = PackageSource()
    
    // MARK: - Initializer
    // MARK: - Test
    @Test("the runner spawns the artifact the manifest actually produces")
    func runnerProductMatchesPackageExecutable() throws {
        // Given
        let manifest = try String(contentsOf: source.manifest, encoding: .utf8)
        
        // When
        let expression = try NSRegularExpression(pattern: #"\.executable\(\s*name:\s*"([^"]+)""#)
        let range = NSRange(manifest.startIndex..., in: manifest)
        let declared = expression.matches(in: manifest, range: range).compactMap { match in
            Range(match.range(at: 1), in: manifest).map { range in String(manifest[range]) }
        }
        
        // Then
        #expect(!declared.isEmpty, "no executable product found in \(source.manifest.path)")
        #expect(declared.contains(CLIRunner.product), """
            The runner spawns SwiftPM's build artifact by name, and SwiftPM names it after the \
            executable product — so a renamed product unplugs the whole integration suite from the \
            product under test. CLIRunner.product is "\(CLIRunner.product)", Package.swift declares \
            \(declared.map { name in "\"\(name)\"" }.joined(separator: ", ")).
            """)
    }
    
    @Test("the binary is present, so a missing build reports once instead of once per test")
    func binaryIsBuiltForTheIntegrationSuite() {
        // When
        let runner = CLIRunner(source: source)
        
        // Then
        #expect(runner.binary != nil, """
            CLI binary not built — every CLI integration test spawns it, so its absence reports as a \
            wall of product failures rather than one broken harness. Searched:
            \(runner.candidates.map(\.path).joined(separator: "\n"))
            """)
    }
}
