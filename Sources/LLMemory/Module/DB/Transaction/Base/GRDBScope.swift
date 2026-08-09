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

    // MARK: - Public
    @discardableResult
    public func run<T: GRDBTransaction>(_ transaction: T) throws -> T.Result {
        try transaction.perform(db)
    }

    // MARK: - Private
}
