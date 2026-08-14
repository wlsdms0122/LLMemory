//
//  Policy.swift
//  LLMemory
//
//  Created by JSilver on 8/7/26.
//

import Foundation

struct Policy: Sendable {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Public
    func fresh(_ alias: String = "n") -> String {
        "COALESCE(\(qualifier(alias))stale, 0) = 0"
    }
    
    func stale(_ alias: String = "n") -> String {
        "COALESCE(\(qualifier(alias))stale, 0) = 1"
    }
    
    func eager(_ alias: String = "n") -> String {
        "\(qualifier(alias))priority = 'eager'"
    }
    
    func notEager(_ alias: String = "n") -> String {
        "\(qualifier(alias))priority != 'eager'"
    }
    
    func forgetExempt(_ alias: String = "n") -> String {
        "\(qualifier(alias))template IS NULL AND \(qualifier(alias))locked = 0"
    }
    
    func surface(_ alias: String = "n") -> String {
        fresh(alias)
    }
    
    func notSurface(_ alias: String = "n") -> String {
        stale(alias)
    }
    
    func decayCandidate(_ alias: String = "n") -> String {
        all(surface(alias), notEager(alias), forgetExempt(alias))
    }
    
    func all(_ parts: String...) -> String {
        parts.filter { part in !part.isEmpty }.joined(separator: " AND ")
    }
    
    // MARK: - Private
    private func qualifier(_ alias: String) -> String {
        alias.isEmpty ? "" : "\(alias)."
    }
}
