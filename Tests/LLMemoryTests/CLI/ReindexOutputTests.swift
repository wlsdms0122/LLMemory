//
//  ReindexOutputTests.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/9/26.
//

import Testing
@testable import LLMemory
@testable import LLMemoryCLI

// The failure → return-code mapping is what "reindex reports failure" means
// to the user — pin it on the pure partition, independent of any home.
@Suite("ReindexOutput Tests")
struct ReindexOutputTests {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Test
    @Test("all successes map to return code 0 and keep both path meanings")
    func allSuccessesMapToReturnCodeZero() {
        // Given
        let outcomes = [
            Indexer.ReindexOutcome(
                filePath: "brain/cortex/flow/a.md",
                result: .reindexed(noteId: "a", relativePath: "cortex/flow/a.md")
            )
        ]

        // When
        let output = IndexBuild.ReindexOutput(outcomes: outcomes)

        // Then
        #expect(output.returnCode == 0)
        #expect(output.reindexed == 1)
        #expect(output.failures.isEmpty)
        #expect(output.files.first?.path == "brain/cortex/flow/a.md")
        #expect(output.files.first?.relativePath == "cortex/flow/a.md")
        #expect(output.files.first?.noteId == "a")
        #expect(output.files.first?.error == nil)
    }

    @Test("one failure flips the return code and stays out of the reindexed count")
    func oneFailureFlipsTheReturnCode() {
        // Given
        let outcomes = [
            Indexer.ReindexOutcome(
                filePath: "brain/cortex/flow/a.md",
                result: .reindexed(noteId: "a", relativePath: "cortex/flow/a.md")
            ),
            Indexer.ReindexOutcome(
                filePath: "brain/.trash/flow/b.md",
                result: .failure("not a live note")
            )
        ]

        // When
        let output = IndexBuild.ReindexOutput(outcomes: outcomes)

        // Then
        #expect(output.returnCode == 1)
        #expect(output.reindexed == 1)
        #expect(output.failures.count == 1)
        #expect(output.failures.first?.path == "brain/.trash/flow/b.md")
        #expect(output.failures.first?.relativePath == nil)
        #expect(output.failures.first?.error == "not a live note")
    }

    // MARK: - Private
}
