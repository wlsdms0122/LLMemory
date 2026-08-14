//
//  WriteGate.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB
import Storage

// An async-safe mutex — NSLock cannot legally span an await (unlock is
// thread-affine), so waiters park as continuations and release may happen on
// any thread. It orders tasks; the guarded body may still block its thread.
final class WriteGate: @unchecked Sendable {
    // MARK: - Property
    private let lock = NSLock()
    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    // MARK: - Initializer
    // MARK: - Public
    func acquire() async {
        await withCheckedContinuation { continuation in
            lock.lock()

            if busy {
                waiters.append(continuation)
                lock.unlock()
            } else {
                busy = true
                lock.unlock()
                continuation.resume()
            }
        }
    }

    func release() {
        lock.lock()

        if waiters.isEmpty {
            busy = false
            lock.unlock()
        } else {
            let next = waiters.removeFirst()
            lock.unlock()
            next.resume()
        }
    }

    // MARK: - Private
}
