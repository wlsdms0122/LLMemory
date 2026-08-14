//
//  TemplateFrameNode.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation

public struct TemplateFrameNode: Encodable, Sendable {
    enum CodingKeys: String, CodingKey {
        case level
        case title
        case guide
        case children
    }
    
    // MARK: - Property
    public let level: Int
    public let title: String
    public let norm: String
    public let guide: String
    public let children: [TemplateFrameNode]
    
    // MARK: - Initializer
    // MARK: - Public
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(level, forKey: .level)
        try container.encode(title, forKey: .title)
        try container.encode(guide, forKey: .guide)
        
        if !children.isEmpty { try container.encode(children, forKey: .children) }
    }
    
    // MARK: - Private
}
