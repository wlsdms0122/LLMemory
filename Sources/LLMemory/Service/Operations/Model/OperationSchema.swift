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
    public let fields: [OperationField]
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
    
    // Whatever an op carries that this schema does not name. For the ops that
    // author a note that is a custom frontmatter field — the caller means it
    // for the note, not for the op, and the note is where it belongs.
    public func undeclaredFields(in op: [String: Any]) -> [String: Any] {
        let declared = Set(fields.map(\.name)).union(["op", "rationale"])
        
        return op.filter { entry in !declared.contains(entry.key) }
    }
    
    // Whether the payload carries what this schema says it must. The list of
    // required names is the schema's own answer to the same payload, so asking
    // and answering stay in one place.
    public func missingRequiredField(in op: [String: Any]) -> String? {
        for field in requiredNames(given: op) {
            if op[field] == nil { return "missing/empty field: \(field)" }
            
            if let value = op[field] as? String, value.isEmpty {
                return "missing/empty field: \(field)"
            }
            
            if op[field] is NSNull { return "missing/empty field: \(field)" }
        }
        
        return nil
    }
    
    // MARK: - Private
}
