//
//  GRDBStorable.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB
import Storage

// What a store is to the tiers above it: the ways a unit of work opens, and
// the lifecycle around them.
//
// `run` is restated rather than inherited so that this store's gating is
// what a caller gets. DBStorable's default runs the transaction against a
// bare connection; a write here has to hold the cross-process lock and the
// in-process gate first, and announce the commit after — none of which a
// default in another module can know about. Declared as a requirement, the
// store's own answer is the one that dispatches, through the protocol as
// well as through the type.
public protocol GRDBStorable: DBStorable where Connection == any DatabaseWriter {
    // MARK: - Lifecycle
    func initialize() throws
    func connection() throws -> any DatabaseWriter
    func disconnect()

    // MARK: - Unit of work
    // A transaction run on its own — the store opens the unit of work
    // around it, gated for writes and ungated for reads.
    @discardableResult
    func run<T: GRDBTransaction>(_ transaction: T) async throws -> T.Result

    @discardableResult
    func run<T: GRDBReadTransaction>(_ transaction: T) async throws -> T.Result

    // A unit of work whose body is domain work, not a query bundle: the
    // services orchestrate inside, and every DB touch within goes through
    // db.run(transaction). Throwing rolls the whole body back.
    @discardableResult
    func write<T: Sendable>(_ body: @escaping @Sendable (Database) throws -> T) async throws -> T

    @discardableResult
    func read<T: Sendable>(_ body: @escaping @Sendable (Database) throws -> T) async throws -> T

    // The sync lifecycle gate — bootstrap, which must run before the
    // migration gate can pass, and test fixtures.
    func writeLock<T>(_ body: () throws -> T) throws -> T
}

public extension GRDBStorable {
    // DBStorable's own door, answered by the synchronous one the lifecycle
    // uses. Opening the connection is not what the async is for.
    func connect() async throws -> any DatabaseWriter { try connection() }
}
