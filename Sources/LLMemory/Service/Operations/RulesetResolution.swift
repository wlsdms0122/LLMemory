//
//  RulesetResolution.swift
//  LLMemory
//
//  Created by JSilver on 8/7/26.
//

import Foundation

public enum RulesetResolution {
    public struct Error: Swift.Error {
        // MARK: - Property
        public let message: String
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    // MARK: - Property
    public static let envRuleset = "LLMEMORY_RULESET"
    public static let envLocked = "LLMEMORY_RULESET_LOCKED"
    
    // MARK: - Initializer
    // MARK: - Public
    public static func resolve(cliRuleset: String?) throws -> String? {
        let envName = nonEmpty(ProcessInfo.processInfo.environment[envRuleset])
        let locked = isTruthy(ProcessInfo.processInfo.environment[envLocked])
        
        if locked {
            guard let envName else {
                throw Error(message: "\(envLocked)=1 set but \(envRuleset) is empty")
            }
            
            return envName
        }
        
        if let cliRuleset = nonEmpty(cliRuleset) { return cliRuleset }
        
        return envName
    }
    
    // MARK: - Private
    private static func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        
        return trimmed.isEmpty ? nil : trimmed
    }
    
    private static func isTruthy(_ value: String?) -> Bool {
        guard let value = value?.lowercased() else { return false }
        
        return ["1", "true", "yes", "on"].contains(value)
    }
}
