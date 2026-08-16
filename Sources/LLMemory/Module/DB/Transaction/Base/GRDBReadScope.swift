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

    // The same handle over a brain whose genome answers one gene differently
    // — what the shadow replay re-runs a logged query against. The borrowed
    // value reaches exactly the transactions run through this scope and
    // nothing else, which a binding could not promise.
    func shadowing(gene: String, value: Double) -> GRDBReadScope {
        GRDBReadScope(db, brain.shadowing(gene: gene, value: value))
    }

    // MARK: - Private
}
