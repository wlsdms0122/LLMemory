//
//  Policy.swift
//  LLMemory
//
//  Created by JSilver on 8/7/26.
//

import Foundation

enum Policy {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Public
    static func fresh(_ alias: String = "n") -> String {
        "COALESCE(\(qualifier(alias))stale, 0) = 0"
    }
    
    static func stale(_ alias: String = "n") -> String {
        "COALESCE(\(qualifier(alias))stale, 0) = 1"
    }
    
    static func eager(_ alias: String = "n") -> String {
        "\(qualifier(alias))priority = 'eager'"
    }
    
    static func notEager(_ alias: String = "n") -> String {
        "\(qualifier(alias))priority != 'eager'"
    }
    
    static func forgetExempt(_ alias: String = "n") -> String {
        "\(qualifier(alias))template IS NULL AND \(qualifier(alias))locked = 0"
    }
    
    static func surface(_ alias: String = "n") -> String {
        fresh(alias)
    }
    
    static func notSurface(_ alias: String = "n") -> String {
        stale(alias)
    }
    
    static func decayCandidate(_ alias: String = "n") -> String {
        all(surface(alias), notEager(alias), forgetExempt(alias))
    }
    
    static func all(_ parts: String...) -> String {
        parts.filter { part in !part.isEmpty }.joined(separator: " AND ")
    }
    
    // MARK: - Private
    private static func qualifier(_ alias: String) -> String {
        alias.isEmpty ? "" : "\(alias)."
    }
}
