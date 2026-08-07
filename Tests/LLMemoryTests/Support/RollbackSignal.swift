//
//  RollbackSignal.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/8/26.
//

import Foundation

// Thrown to abort a transaction on purpose. A test that wants to see a rollback needs a failure that
// cannot be confused with a real one.
struct RollbackSignal: Error {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}
