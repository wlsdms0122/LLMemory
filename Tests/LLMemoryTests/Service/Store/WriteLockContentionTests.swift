//
//  WriteLockContentionTests.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/9/26.
//

import Testing
import Foundation
import GRDB
@testable import LLMemory

// Two GRDBStorage instances over one database file open separate descriptors,
// so flock(2) contends between them exactly as it does between two CLI
// processes — the cross-process write exclusion, verified deterministically.
@Suite("WriteLockContention Tests", .serialized)
struct WriteLockContentionTests {
    // MARK: - Property
    private let home: MemoryHome

    // MARK: - Initializer
    init() throws {
        home = try MemoryHome()
    }

    // MARK: - Test
    @Test("a second storage's write section waits for the first to release the lock")
    func writeSectionsAreMutuallyExclusive() throws {
        // Given — a rival storage over the same database file, as a second process would open.
        let rival = GRDBStorage(
            databaseURL: home.url.appendingPathComponent("data/memory.db"),
            migrations: Session.migrations
        )
        let holderEntered = DispatchSemaphore(value: 0)
        let releaseHolder = DispatchSemaphore(value: 0)
        let order = Recorder()

        // When — the fixture's storage holds its write section open while the
        // rival tries to enter one of its own.
        let holder = Thread {
            try? home.storage.writeLock {
                order.mark("holder-in")
                holderEntered.signal()
                releaseHolder.wait()
                order.mark("holder-out")
            }
        }
        holder.start()
        holderEntered.wait()

        let rivalDone = DispatchSemaphore(value: 0)
        let rivalThread = Thread {
            try? rival.writeLock {
                order.mark("rival-in")
            }
            rivalDone.signal()
        }
        rivalThread.start()

        // Give the rival a real chance to (wrongly) slip in before the release.
        Thread.sleep(forTimeInterval: 0.2)
        releaseHolder.signal()

        #expect(rivalDone.wait(timeout: .now() + 5) == .success, "the rival never acquired the lock — release did not propagate")

        // Then — the rival entered only after the holder left.
        let observed = order.snapshot()

        #expect(observed == ["holder-in", "holder-out", "rival-in"], "write sections overlapped across storages: \(observed)")
    }

    // MARK: - Private
    private final class Recorder: @unchecked Sendable {
        // MARK: - Property
        private let lock = NSLock()
        private var order: [String] = []

        // MARK: - Initializer
        // MARK: - Public
        func mark(_ label: String) {
            lock.lock()
            order.append(label)
            lock.unlock()
        }

        func snapshot() -> [String] {
            lock.lock()

            defer { lock.unlock() }

            return order
        }

        // MARK: - Private
    }
}
