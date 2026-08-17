//
//  Database+Transaction.swift
//  LLMemory
//
//  Created by JSilver on 8/17/26.
//

import Foundation
import GRDB

// Running a transaction against an open handle.
//
// There is no wrapper type here on purpose. A handle that only forwards to
// the handle it holds is a second way to say the same thing, and the two
// drift: it grew its own entry point, its own read/write pair, and its own
// initializer, none of which the storage protocol knew about. What the
// wrapper actually contributed was the savepoint below, and a savepoint is
// a property of running a transaction, not of holding a connection.
public extension Database {
    // MARK: - Public
    // Every write transaction is its own atomic unit — a SAVEPOINT wraps
    // perform, so a failure a caller swallows (try?) cannot leave half the
    // transaction's statements behind in the enclosing commit. The unit of
    // work remains the outer rollback boundary; savepoints nest freely.
    @discardableResult
    func run<T: GRDBTransaction>(_ transaction: T) throws -> T.Result {
        var result: T.Result!

        try inSavepoint {
            result = try transaction.perform(self)

            return .commit
        }

        return result
    }

    // A read transaction has nothing to roll back — the atomicity marker
    // stays on writes; the more specific overload wins for read conformers.
    @discardableResult
    func run<T: GRDBReadTransaction>(_ transaction: T) throws -> T.Result {
        try transaction.perform(self)
    }

    // A savepointed best-effort — the body either commits whole or rolls
    // back whole, and the failure comes back as a value instead of being
    // swallowed at the call site.
    func attempt<T>(_ body: () throws -> T) throws -> Swift.Result<T, any Error> {
        var outcome: Swift.Result<T, any Error>!

        try inSavepoint {
            do {
                outcome = .success(try body())

                return .commit
            } catch {
                outcome = .failure(error)

                return .rollback
            }
        }

        return outcome
    }
}
