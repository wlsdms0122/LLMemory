//
//  SplitConflict.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation

public struct SplitConflict: Error, Encodable, Sendable {
    public enum CodingKeys: String, CodingKey {
        case fromId = "from_id"
        case unresolved = "unresolved"
    }
    
    // MARK: - Property
    public let fromId: String
    public let unresolved: [RouteArtifact]
    
    // MARK: - Initializer
    // MARK: - Public
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(fromId, forKey: .fromId)
        try container.encode(unresolved, forKey: .unresolved)
    }
    
    // MARK: - Private
}
