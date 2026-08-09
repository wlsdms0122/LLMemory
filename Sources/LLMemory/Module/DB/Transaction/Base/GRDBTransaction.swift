//
//  GRDBTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import GRDB

// A transaction is the DB module's vocabulary — a reusable, synchronous
// bundle of queries over a database handle. It claims no atomicity: the
// rollback boundary (flock + BEGIN/COMMIT) belongs to the storage scope
// that runs it, so the same transaction composes into any unit of work
// and any number of services share it.
public protocol GRDBTransaction: Sendable {
    associatedtype Result

    @discardableResult
    func perform(_ db: Database) throws -> Result
}

// A transaction that only reads — the read scope accepts these alone, so
// writing from a read path is a compile error again, not a runtime
// SQLITE_READONLY surprise.
public protocol GRDBReadTransaction: GRDBTransaction { }
