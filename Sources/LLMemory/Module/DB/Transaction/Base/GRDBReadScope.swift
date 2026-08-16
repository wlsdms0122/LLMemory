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
    let brain: BrainContext

    private let db: Database

    // MARK: - Initializer
    init(_ db: Database, _ brain: BrainContext) {
        self.db = db
        self.brain = brain
    }

    // MARK: - Public
    @discardableResult
    public func run<T: GRDBReadTransaction>(_ transaction: T) throws -> T.Result {
        try transaction.perform(db)
    }

    @discardableResult
    public func run<T: GRDBBrainReadTransaction>(_ transaction: T) throws -> T.Result {
        try transaction.perform(db, brain)
    }

    // MARK: - Private
}
