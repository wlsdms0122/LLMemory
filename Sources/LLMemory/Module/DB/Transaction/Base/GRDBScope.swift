//
//  GRDBScope.swift
//  LLMemory
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import GRDB

// The write handle services orchestrate through — runs transactions against
// the connection bound to the enclosing storage scope. Deliberately not
// Sendable: a scope must not outlive the block that owns its rollback
// boundary.
public struct GRDBScope {
    // MARK: - Property
    private let db: Database

    // MARK: - Initializer
    init(_ db: Database) {
        self.db = db
    }

    public enum SavepointOutcome {
        case commit
        case rollback
    }

    // MARK: - Public
    @discardableResult
    public func run<T: GRDBTransaction>(_ transaction: T) throws -> T.Result {
        try transaction.perform(db)
    }

    // A nested rollback unit inside the scope — the operation engine rolls
    // an op sequence back while the enclosing scope stays alive to record
    // the failure.
    public func savepoint(_ body: () throws -> SavepointOutcome) throws {
        try db.inSavepoint {
            switch try body() {
            case .commit:
                return .commit

            case .rollback:
                return .rollback
            }
        }
    }

    // A savepointed best-effort — the body either commits whole or rolls
    // back whole, and the failure comes back as a value instead of being
    // swallowed at the call site.
    public func attempt<T>(_ body: () throws -> T) throws -> Swift.Result<T, any Error> {
        var outcome: Swift.Result<T, any Error>!

        try savepoint {
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

    // A write scope may always be viewed as a read scope — read cores take
    // GRDBReadScope and write orchestrators downgrade to call them.
    public var readOnly: GRDBReadScope { GRDBReadScope(db) }

    // MARK: - Private
}

// The read handle — accepts read transactions alone, so a write issued
// from a read path fails at compile time.
public struct GRDBReadScope {
    // MARK: - Property
    private let db: Database

    // MARK: - Initializer
    init(_ db: Database) {
        self.db = db
    }

    // MARK: - Public
    @discardableResult
    public func run<T: GRDBReadTransaction>(_ transaction: T) throws -> T.Result {
        try transaction.perform(db)
    }

    // MARK: - Private
}
