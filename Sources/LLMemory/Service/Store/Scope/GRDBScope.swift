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
    // The brain this scope was opened on. A transaction that reads a
    // parameter takes it from here, in its signature, instead of resolving
    // whichever brain the process saw last.
    let brain: BrainContext

    private let db: Database

    // MARK: - Initializer
    init(_ db: Database, _ brain: BrainContext) {
        self.db = db
        self.brain = brain
    }

    public enum SavepointOutcome {
        case commit
        case rollback
    }

    // MARK: - Public
    // Every write transaction is its own atomic unit — a SAVEPOINT wraps
    // perform, so a failure a caller swallows (try?) cannot leave half the
    // transaction's statements behind in the scope's commit. The scope
    // remains the outer rollback boundary; savepoints nest freely.
    @discardableResult
    public func run<T: GRDBTransaction>(_ transaction: T) throws -> T.Result {
        var result: T.Result!

        try db.inSavepoint {
            result = try transaction.perform(db)

            return .commit
        }

        return result
    }

    @discardableResult
    public func run<T: GRDBBrainTransaction>(_ transaction: T) throws -> T.Result {
        var result: T.Result!

        try db.inSavepoint {
            result = try transaction.perform(db, brain)

            return .commit
        }

        return result
    }

    @discardableResult
    public func run<T: GRDBBrainReadTransaction>(_ transaction: T) throws -> T.Result {
        try transaction.perform(db, brain)
    }

    // A read transaction has nothing to roll back — the atomicity marker
    // stays on writes; the more specific overload wins for read conformers.
    @discardableResult
    public func run<T: GRDBReadTransaction>(_ transaction: T) throws -> T.Result {
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
    public var readOnly: GRDBReadScope { GRDBReadScope(db, brain) }

    // MARK: - Private
}
