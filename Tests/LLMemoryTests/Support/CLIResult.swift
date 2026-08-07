//
//  CLIResult.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/8/26.
//

import Foundation

struct CLIResult {
    // MARK: - Property
    let exitCode: Int32
    let standardOutput: String
    let standardError: String
    
    var succeeded: Bool { exitCode == 0 }
    
    // MARK: - Initializer
    // MARK: - Public
    func json() -> Any? {
        guard let data = standardOutput.data(using: .utf8) else { return nil }
        
        return try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }
    
    func jsonArray() -> [[String: Any]]? { json() as? [[String: Any]] }
    
    func jsonObject() -> [String: Any]? { json() as? [String: Any] }
    
    func rows() -> [[String: Any]] {
        if let array = jsonArray() { return array }
        
        return (jsonObject()?["rows"] as? [[String: Any]]) ?? []
    }
    
    func ids() -> [String] {
        rows().compactMap { row in row["id"] as? String }
    }
    
    // MARK: - Private
}
