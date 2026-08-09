//
//  OperationsUnavailableTests.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/10/26.
//

import Foundation
import Testing
@testable import LLMemory

// The "failure is a status" contract on the production gate itself: a storage
// that cannot connect must normalize to `unavailable` — nothing ran, nothing
// was interpreted. No home fixture is involved (the storage never opens), so
// awaiting here holds no fixture lock.
@Suite("OperationsUnavailable Tests")
struct OperationsUnavailableTests {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Test
    @Test("a connect failure is normalized to the unavailable status, not an exception")
    func connectFailureNormalizesToUnavailable() async {
        // Given
        let home = "/nonexistent-\(UUID().uuidString)"
        let storage = GRDBStorage(
            databaseURL: URL(fileURLWithPath: "\(home)/data/memory.db"),
            migrations: [],
            context: BrainContext(home: home)
        )
        let operations = Container(storage: storage).operations

        // When
        let applied = await operations.apply(
            payloadJSON: #"{"ops":[{"op":"flag","id":"x","kind":"reconsolidate","reason":"r"}],"rationale":"r"}"#
        )
        let dryRun = await operations.dryRun(
            payloadJSON: #"{"ops":[{"op":"flag","id":"x","kind":"reconsolidate","reason":"r"}],"rationale":"r"}"#
        )

        // Then
        #expect(applied.status == "unavailable", "\(applied.status): \(applied.error)")
        #expect(dryRun.status == "unavailable", "\(dryRun.status): \(dryRun.error ?? "")")
    }

    // MARK: - Private
}
