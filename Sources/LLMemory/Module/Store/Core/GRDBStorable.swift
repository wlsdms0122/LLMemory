//
//  GRDBStorable.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB
import Storage

// A store as the tiers above it use one: the ways a unit of work opens.
//
// Nothing else is here. Opening, migrating, caching and closing the
// connection are the composition root's business — Session builds the store
// and is the only thing in Sources that sequences its lifecycle — so those
// stay on the concrete type rather than being re-declared as an interface
// no service calls.
//
// `run` is the exception, and only because it must be. DBStorable supplies
// it, but its default runs the transaction against a bare connection, while
// a write here has to hold the cross-process lock and the in-process gate
// first and announce the commit after. Declared as a requirement, the
// store's own answer is the one that dispatches, through the protocol as
// well as through the type.
public protocol GRDBStorable: DBStorable where Connection == any DatabaseWriter {
    @discardableResult
    func run<T: GRDBTransaction>(_ transaction: T) async throws -> T.Result

    @discardableResult
    func run<T: GRDBReadTransaction>(_ transaction: T) async throws -> T.Result

    // A unit of work whose body is domain work rather than a query bundle:
    // the service orchestrates inside, and every DB touch within goes
    // through db.run(transaction). Throwing rolls the whole body back.
    @discardableResult
    func write<T: Sendable>(_ body: @escaping @Sendable (Database) throws -> T) async throws -> T

    @discardableResult
    func read<T: Sendable>(_ body: @escaping @Sendable (Database) throws -> T) async throws -> T
}
