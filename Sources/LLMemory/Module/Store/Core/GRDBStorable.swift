//
//  GRDBStorable.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB
import Storage

// A brain's store, as the services above it use one.
//
// Two scopes, because a brain has two. `run` is one operation in one
// transaction — the database's own boundary, and the everyday one. `exclusive`
// is wider than the database: it fences the whole brain, which is what work
// spanning the catalogue and the notes beside it needs, and what a transaction
// cannot express.
//
// A write inside `run` takes the wide fence too. Nothing above has to know
// that, which is the point of both living behind one contract.
public protocol GRDBStorable: Sendable {
    @discardableResult
    func run<T: GRDBOperation>(_ operation: T) async throws -> T.Result

    func exclusive<T>(_ body: @Sendable () async throws -> T) async throws -> T
}

public extension GRDBStorable {
    // A unit of work whose body is domain work rather than a query bundle: the
    // service orchestrates inside, calling operations on the transaction it was
    // handed. Throwing rolls the whole body back.
    //
    // It is an operation like any other — the closure is the body `execute`
    // would have held — so it goes through `run` rather than reaching for a
    // transaction itself.
    @discardableResult
    func write<T: Sendable>(_ body: @escaping @Sendable (Database) throws -> T) async throws -> T {
        try await run(Perform(body))
    }

    @discardableResult
    func read<T: Sendable>(_ body: @escaping @Sendable (Database) throws -> T) async throws -> T {
        try await run(Perform(readOnly: true, body))
    }
}

// An operation whose work is a closure rather than a type.
//
// Naming a type per query bundle is what makes the vocabulary reusable, and
// most work earns it. A body that only orchestrates other operations for one
// caller does not — there is nothing to reuse, and a type per call site would
// be a name that exists to be spelled once.
public struct Perform<Result: Sendable>: GRDBOperation {
    // MARK: - Property
    public typealias Parameter = @Sendable (Database) throws -> Result

    public let readOnly: Bool

    private let body: @Sendable (Database) throws -> Result

    // MARK: - Initializer
    public init(readOnly: Bool = false, _ body: @escaping @Sendable (Database) throws -> Result) {
        self.readOnly = readOnly
        self.body = body
    }

    // MARK: - Public
    @discardableResult
    public func execute(_ db: Database) throws -> Result {
        try body(db)
    }
}
