//
//  TestFailure.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/8/26.
//

import Foundation

// Thrown when a fixture cannot reach the state the test asked for. A fixture that returns a broken
// object instead reports as a wall of unrelated expectation failures.
struct TestFailure: Error, CustomStringConvertible {
    // MARK: - Property
    let message: String
    
    var description: String { message }
    
    // MARK: - Initializer
    init(_ message: String) {
        self.message = message
    }
    
    // MARK: - Public
    // MARK: - Private
}
