//
//  GRDBStorable.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

// What a store is to the tiers above it: three ways to open a unit of work,
// and the lifecycle around them.
//
// It does not refine Storage.DBStorable, and the reason is checkable rather
// than a matter of taste. That protocol's unit of work is `DBTransaction`,
// whose `execute` is `async` — so a generic caller must await it, and the
// handle these transactions run against only exists inside GRDB's
// synchronous write block, where awaiting is not possible. The conformance
// was declared anyway and never once used: nothing asked for the protocol,
// no transaction adopted `DBTransaction`, and the `run` that was actually
// called was a second, differently-shaped method that merely shared the
// name. A protocol nobody can honour is not an abstraction, it is a label.
public protocol GRDBStorable: Sendable {
    // MARK: - Lifecycle
    func initialize() throws
    func connect() throws -> any DatabaseWriter
    func disconnect()
    func reset() throws

    // MARK: - Unit of work
    // One flock + one BEGIN/COMMIT around the whole body. Services
    // orchestrate domain work inside; every DB touch goes through
    // db.run(transaction). Throwing rolls the entire body back.
    @discardableResult
    func write<T: Sendable>(_ body: @escaping @Sendable (Database) throws -> T) async throws -> T

    // No lock, no write transaction; SQLite rejects writes issued inside.
    @discardableResult
    func read<T: Sendable>(_ body: @escaping @Sendable (Database) throws -> T) async throws -> T

    // The sync lifecycle gate — bootstrap, which must run before the
    // migration gate can pass, and test fixtures.
    func writeLock<T>(_ body: () throws -> T) throws -> T
}
