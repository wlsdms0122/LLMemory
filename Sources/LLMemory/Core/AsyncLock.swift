//
//  AsyncLock.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import os

// A mutex that may be held across an await. The platform locks cannot be:
// unlock is thread-affine, and a task that suspends inside the critical
// section can resume on another thread. So waiters park as continuations and
// the lock itself only ever guards the queue — held for a few instructions,
// never across a suspension.
//
// It orders tasks; the guarded body may still block its thread.
final class AsyncLock: Sendable {
    // MARK: - Property
    // The state lives inside the lock rather than beside it, so there is no
    // spelling of this type that reads busy or waiters without holding it.
    private struct State {
        var busy = false
        var waiters: [CheckedContinuation<Void, Never>] = []
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    // MARK: - Initializer
    // MARK: - Public
    func acquire() async {
        await withCheckedContinuation { continuation in
            let acquired = state.withLock { state in
                guard state.busy else {
                    state.busy = true

                    return true
                }

                state.waiters.append(continuation)

                return false
            }

            // Resumed after the lock is dropped — a resume can run the woken
            // task inline, and that task's first act may be to acquire again.
            if acquired {
                continuation.resume()
            }
        }
    }

    func release() {
        let next = state.withLock { state -> CheckedContinuation<Void, Never>? in
            guard !state.waiters.isEmpty else {
                state.busy = false

                return nil
            }

            return state.waiters.removeFirst()
        }

        next?.resume()
    }

    // MARK: - Private
}
