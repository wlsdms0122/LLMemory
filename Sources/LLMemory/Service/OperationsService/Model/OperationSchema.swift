//
//  OperationSchema.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation

public struct OperationSchema: Sendable, Encodable {
    // MARK: - Property
    public let summary: String
    public let fields: [OpField]
    public let example: String
    
    public var requiredNames: [String] { fields.filter(\.required).map(\.name) }
    
    // MARK: - Initializer
    // MARK: - Public
    public func mentionedNoteIds(in op: [String: Any]) -> Set<String> {
        var mentioned: Set<String> = []
        
        for field in fields {
            switch field.role {
            case .noteId:
                if let noteId = op[field.name] as? String, !noteId.isEmpty {
                    mentioned.insert(noteId)
                }
            
            case .noteIdList:
                for value in (op[field.name] as? [Any]) ?? [] {
                    if let noteId = value as? String, !noteId.isEmpty {
                        mentioned.insert(noteId)
                    }
                }
            
            case .childSpecs:
                for spec in (op[field.name] as? [[String: Any]]) ?? [] {
                    if let noteId = spec["id"] as? String, !noteId.isEmpty {
                        mentioned.insert(noteId)
                    }
                }
            
            case .plain:
                break
            }
        }
        
        return mentioned
    }
    
    public func requiredNames(given op: [String: Any]) -> [String] {
        fields.filter { field in
            guard field.required else { return false }
            
            if let waiver = field.requiredUnless,
                let value = op[waiver] as? String, !value.isEmpty {
                return false
            }
            
            return true
        }.map(\.name)
    }
    
    // MARK: - Private
}
