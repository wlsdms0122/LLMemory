//
//  GRDBReadScope.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

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
