//
//  GRDBScope.swift
//  LLMemory
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import GRDB

// The handle services orchestrate through — runs transactions against the
// connection bound to the enclosing storage scope. Deliberately not
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

    // MARK: - Private
}
