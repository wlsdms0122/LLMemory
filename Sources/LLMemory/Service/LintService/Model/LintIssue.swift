//
//  LintIssue.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation

// One finding, as it leaves the inspector. `key` is the finding's identity
// within its code and target — it is what a keep-decision is recorded
// against, so a rule reporting several findings on one note must give each
// of them one.
public struct LintIssue: Encodable, Sendable {
    public enum CodingKeys: String, CodingKey {
        case severity, code, message, subject
        case targetScope = "target_scope"
    }
    
    // MARK: - Property
    public let severity: String
    public let code: String
    public let message: String
    public let target: LintTarget
    let key: String?
    
    var dismissalKey: String { key ?? code }
    
    // MARK: - Initializer
    public init(
        _ severity: String,
        _ code: String,
        _ message: String,
        _ target: LintTarget,
        key: String? = nil
    ) {
        self.severity = severity
        self.code = code
        self.message = message
        self.target = target
        self.key = key
    }
    
    // MARK: - Public
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(severity, forKey: .severity)
        try container.encode(code, forKey: .code)
        try container.encode(message, forKey: .message)
        try container.encode(target.scope, forKey: .targetScope)
        try container.encode(target.subject, forKey: .subject)
    }
    
    // MARK: - Private
}
