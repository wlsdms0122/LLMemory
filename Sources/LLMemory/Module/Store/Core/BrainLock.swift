//
//  BrainLock.swift
//  LLMemory
//
//  Created by JSilver on 8/18/26.
//

import Foundation

@_silgen_name("flock") private func c_flock(_ fd: Int32, _ op: Int32) -> Int32

// Exclusive use of one brain, across processes.
//
// What it guards is wider than the database: a brain is markdown under
// `cortex/` and a SQLite catalogue derived from it, and the two have to move
// together. A transaction cannot say that — it knows only rows — so the fence
// that can is a file lock beside them, and it belongs here rather than inside
// a store that would be claiming authority over files it never touches.
//
// SQLite already serializes concurrent writers to the database on its own
// (WAL, plus a busy timeout). This exists for the work that database locking
// cannot see: migrating, writing notes to disk, rebuilding the index.
final class BrainLock: @unchecked Sendable {
    // MARK: - Property
    private let path: URL

    // flock cannot separate two tasks of one process — they share the
    // descriptor — so an in-process gate is what makes the depth count sound.
    // It is taken first, and every holder passes through it.
    private let gate = AsyncLock()
    private let mutex = NSLock()

    private var descriptor: Int32 = -1
    private var depth = 0

    // MARK: - Initializer
    init(dataDirectory: URL) {
        self.path = dataDirectory.appendingPathComponent(".write.lock")
    }

    deinit {
        if descriptor >= 0 {
            _ = Darwin.close(descriptor)
        }
    }

    // MARK: - Public
    // Holds the brain for the duration. Re-entrant: work composed inside a
    // scope that already holds the lock joins it rather than deadlocking on
    // itself, which is what lets a caller wrap a body that runs operations.
    func exclusive<T>(_ body: () async throws -> T) async throws -> T {
        await gate.acquire()

        defer { gate.release() }

        try acquire()

        defer { release() }

        return try await body()
    }

    // MARK: - Private
    private func acquire() throws {
        mutex.lock()

        defer { mutex.unlock() }

        if descriptor < 0 {
            let directory = path.deletingLastPathComponent()

            guard FileManager.default.fileExists(atPath: directory.path) else {
                throw DBError.dataDirMissing(directory.path)
            }

            let opened = Darwin.open(path.path, O_WRONLY | O_CREAT, 0o644)

            guard opened >= 0 else {
                throw DBError.lockFailed(errno: errno)
            }

            descriptor = opened
        }

        if depth == 0 {
            guard c_flock(descriptor, LOCK_EX) == 0 else {
                throw DBError.lockFailed(errno: errno)
            }
        }

        depth += 1
    }

    private func release() {
        mutex.lock()

        defer { mutex.unlock() }

        depth -= 1

        if depth == 0, descriptor >= 0 {
            _ = c_flock(descriptor, LOCK_UN)
        }
    }
}
