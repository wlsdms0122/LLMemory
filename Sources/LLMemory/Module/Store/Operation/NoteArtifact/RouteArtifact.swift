//
//  RouteArtifact.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

public struct RouteArtifact: Encodable, Equatable, Sendable {
    enum CodingKeys: String, CodingKey {
        case type, kind, neighbor, term
    }
    
    // MARK: - Property
    public let type: String
    public let kind: String?
    public let neighbor: String?
    public let term: String?
    
    // MARK: - Initializer
    // MARK: - Public
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(type, forKey: .type)
        
        if let kind { try container.encode(kind, forKey: .kind) }
        if let neighbor { try container.encode(neighbor, forKey: .neighbor) }
        if let term { try container.encode(term, forKey: .term) }
    }
    
    // MARK: - Private
}
