//
//  GRDBStorable.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB
import Storage

// A store as the tiers above it use one, pinned to what GRDB calls a
// connection and an open transaction.
//
// Nothing is added. `run` comes from DBStorable and reaches the database only
// through `open`, which is where this store puts the cross-process lock, the
// in-process gate and the commit announcement — so the gating holds for every
// caller without a single requirement being restated here.
public protocol GRDBStorable: DBStorable where Connection == any DatabaseWriter, Transaction == Database { }

public extension GRDBStorable {
    // A unit of work whose body is domain work rather than a query bundle: the
    // service orchestrates inside, calling operations on the transaction it was
    // handed. Throwing rolls the whole body back.
    //
    // It is an operation like any other — the closure is the body `execute`
    // would have held — so it goes through `run`, and the store's hooks see it.
    @discardableResult
    func write<T>(_ body: @escaping @Sendable (Database) throws -> T) async throws -> T {
        try await run(Perform(body))
    }

    @discardableResult
    func read<T>(_ body: @escaping @Sendable (Database) throws -> T) async throws -> T {
        try await run(PerformReading(body))
    }
}

// An operation whose work is a closure rather than a type.
//
// Naming a type per query bundle is what makes the vocabulary reusable, and
// most work earns it. A body that only orchestrates other operations for one
// caller does not — there is nothing to reuse, and a type per call site would
// be a name that exists to be spelled once.
public struct Perform<Result>: GRDBOperation {
    // MARK: - Property
    private let body: @Sendable (Database) throws -> Result

    // MARK: - Initializer
    public init(_ body: @escaping @Sendable (Database) throws -> Result) {
        self.body = body
    }

    // MARK: - Public
    @discardableResult
    public func execute(_ db: Database) throws -> Result {
        try body(db)
    }
}

public struct PerformReading<Result>: GRDBReadOperation {
    // MARK: - Property
    private let body: @Sendable (Database) throws -> Result

    // MARK: - Initializer
    public init(_ body: @escaping @Sendable (Database) throws -> Result) {
        self.body = body
    }

    // MARK: - Public
    @discardableResult
    public func execute(_ db: Database) throws -> Result {
        try body(db)
    }
}
