//
//  Database+Savepoint.swift
//  LLMemory
//
//  Created by JSilver on 8/17/26.
//

import Foundation
import GRDB

// A savepoint is the only thing an operation running inside an open
// transaction can add to it: a nested boundary that rolls back alone.
//
// There is no entry point here for running an operation — that is
// `operation.execute(db)`, and a second spelling of it would be a second
// answer to a question the store already answers.
public extension Database {
    // MARK: - Public
    // A savepointed best-effort — the body either commits whole or rolls back
    // whole, and the failure comes back as a value instead of being swallowed
    // at the call site.
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
