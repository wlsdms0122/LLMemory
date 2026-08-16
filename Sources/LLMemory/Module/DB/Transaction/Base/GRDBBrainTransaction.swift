//
//  GRDBBrainTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/16/26.
//

import Foundation
import GRDB

// A transaction that reads more of a brain than its database: where its files
// live, what its configuration says, what its genes are set to. Declaring it
// is the whole point — the dependency is in the signature, and a transaction
// that does not declare it has no way to reach those values at all.
public protocol GRDBBrainTransaction: Sendable {
    associatedtype Result

    @discardableResult
    func perform(_ db: Database, _ brain: BrainContext) throws -> Result
}

// The read-only half, for the same reason GRDBReadTransaction exists: a read
// scope accepts these alone, so writing from a read path stays a compile error.
public protocol GRDBBrainReadTransaction: GRDBBrainTransaction { }
