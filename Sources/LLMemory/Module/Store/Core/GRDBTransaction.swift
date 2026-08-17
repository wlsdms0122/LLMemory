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
// rollback boundary (flock + BEGIN/COMMIT) belongs to the unit of work the
// storage opened around it, so the same transaction composes into any of
// them and any number of services share it.
public protocol GRDBTransaction: Sendable {
    associatedtype Result

    @discardableResult
    func perform(_ db: Database) throws -> Result
}
