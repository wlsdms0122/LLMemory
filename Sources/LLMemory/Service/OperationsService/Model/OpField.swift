//
//  OpField.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation

public struct OpField: Sendable, Encodable {
    enum CodingKeys: String, CodingKey {
        case name
        case required
        case description
        case requiredUnless = "required_unless"
    }
    
    // MARK: - Property
    public let name: String
    public let required: Bool
    public let description: String
    public let requiredUnless: String?
    public let role: OpFieldRole
    
    // MARK: - Initializer
    // MARK: - Public
    public static func required(
        _ name: String,
        role: OpFieldRole = .plain,
        _ description: String
    ) -> OpField {
        OpField(
            name: name,
            required: true,
            description: description,
            requiredUnless: nil,
            role: role
        )
    }
    
    public static func optional(
        _ name: String,
        role: OpFieldRole = .plain,
        _ description: String
    ) -> OpField {
        OpField(
            name: name,
            required: false,
            description: description,
            requiredUnless: nil,
            role: role
        )
    }
    
    public static func required(
        _ name: String,
        unless waiver: String,
        role: OpFieldRole = .plain,
        _ description: String
    ) -> OpField {
        OpField(
            name: name,
            required: true,
            description: description,
            requiredUnless: waiver,
            role: role
        )
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(name, forKey: .name)
        try container.encode(required, forKey: .required)
        try container.encode(description, forKey: .description)
        
        if let requiredUnless {
            try container.encode(requiredUnless, forKey: .requiredUnless)
        }
    }
    
    // MARK: - Private
}
