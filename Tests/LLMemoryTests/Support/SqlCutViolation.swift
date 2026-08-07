//
//  SqlCutViolation.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/8/26.
//

import Foundation

struct SqlCutViolation: CustomStringConvertible {
    // MARK: - Property
    let file: String
    let line: Int
    let reason: String
    let snippet: String
    
    var description: String { "\(file):\(line) — \(reason) — \(snippet)" }
    
    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}
