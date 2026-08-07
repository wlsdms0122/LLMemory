//
//  EnvironmentOverride.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/8/26.
//

import Foundation

// Sets environment variables for the duration of one call and puts the previous values back, whether
// the body returns or throws. Tests that read the process environment would otherwise leak state into
// whichever test runs next.
struct EnvironmentOverride {
    // MARK: - Property
    private let variables: [String: String?]
    
    // MARK: - Initializer
    init(_ variables: [String: String?]) {
        self.variables = variables
    }
    
    // MARK: - Public
    func callAsFunction(_ body: () throws -> Void) rethrows {
        let previous: [String: String?] = variables.reduce(into: [:]) { result, entry in
            result[entry.key] = ProcessInfo.processInfo.environment[entry.key]
        }
        
        Self.set(variables)
        
        defer { Self.set(previous) }
        
        try body()
    }
    
    // MARK: - Private
    private static func set(_ variables: [String: String?]) {
        for (key, value) in variables {
            if let value {
                setenv(key, value, 1)
            } else {
                unsetenv(key)
            }
        }
    }
}
