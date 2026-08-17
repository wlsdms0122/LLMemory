//
//  OpenRoutingTests.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/18/26.
//

import Testing
import Foundation
import GRDB
@testable import LLMemory

// `open(readOnly:_:)` is the one path an operation reaches the database
// through, so what it does with the flag is the whole gating contract: a write
// waits for the cross-process lock, a read never asks for it. Two storages over
// one file contend exactly as two CLI processes do.
//
// The tests stay synchronous so they can block on a semaphore — the operation
// under test is the async one, and it runs in a Task that signals when it lands.
@Suite("OpenRouting Tests", .serialized)
struct OpenRoutingTests {
    // MARK: - Property
    private let home: MemoryHome

    // MARK: - Initializer
    init() throws {
        home = try MemoryHome()
    }

    // MARK: - Test
    @Test("a read operation runs while another storage holds the write lock")
    func readsDoNotWaitForTheWriteLock() throws {
        // Given — a rival storage over the same file, and the lock held elsewhere.
        let rival = makeRival()
        let release = DispatchSemaphore(value: 0)

        holdWriteLock(until: release)

        defer { release.signal() }

        // When — the rival runs a read while the holder is still inside.
        let finished = DispatchSemaphore(value: 0)

        Task {
            defer { finished.signal() }

            _ = try await rival.run(CountEagerNotesOperation())
        }

        // Then — it came back without the holder ever leaving.
        #expect(
            finished.wait(timeout: .now() + 5) == .success,
            "the read waited on a lock it has no business taking"
        )
    }

    @Test("a write operation waits for the lock another storage holds")
    func writesWaitForTheWriteLock() throws {
        // Given
        let rival = makeRival()
        let release = DispatchSemaphore(value: 0)

        holdWriteLock(until: release)

        // When — the rival writes while the holder is still inside.
        let finished = DispatchSemaphore(value: 0)

        Task {
            defer { finished.signal() }

            try await rival.run(
                RecordEventOperation(kind: .consolidation, payload: EventPayload([:]), ts: home.now)
            )
        }

        // Then — it is still waiting, and only lands once the holder leaves.
        #expect(
            finished.wait(timeout: .now() + 1) == .timedOut,
            "the write slipped past a lock another storage was holding"
        )

        release.signal()

        #expect(finished.wait(timeout: .now() + 5) == .success, "the write never acquired the lock")
    }

    // MARK: - Private
    private func makeRival() -> GRDBStorage {
        GRDBStorage(
            databaseURL: home.url.appendingPathComponent("data/memory.db"),
            migrations: Session.migrations
        )
    }

    // Takes the fixture storage's write section on a thread of its own and stays
    // there until released — the other process, standing still.
    private func holdWriteLock(until release: DispatchSemaphore) {
        let held = DispatchSemaphore(value: 0)
        let holder = Thread {
            try? home.storage.writeLock {
                held.signal()
                release.wait()
            }
        }

        holder.start()
        held.wait()
    }
}
