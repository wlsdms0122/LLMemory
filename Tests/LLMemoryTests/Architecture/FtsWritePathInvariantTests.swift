//
//  FtsWritePathInvariantTests.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import Testing

@Suite("FtsWritePathInvariant Tests")
struct FtsWritePathInvariantTests {
    // MARK: - Property
    private let source = PackageSource()
    
    // MARK: - Initializer
    // MARK: - Test
    @Test("notes_fts is written from one place — a second writer is a second definition of the index")
    func ftsInsertsOnlyInNotesService() {
        // Given
        let sources = source.files(in: "Sources").map(SwiftSourceFile.init)
        
        #expect(!sources.isEmpty, "no sources found under \(source.root.path)")
        
        // When
        let violations = sources
            .filter { file in file.name != "ReindexNoteFTSTransaction.swift" }
            .filter { file in file.text.contains("INSERT INTO notes_fts") }
            .map(\.name)
        
        // Then
        #expect(violations.isEmpty, """
            notes_fts must be written only through ReindexNoteFTSTransaction — a second writer means the \
            index has two definitions of what a row is. Offending files: \
            \(violations.joined(separator: ", "))
            """)
    }
}
