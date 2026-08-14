//
//  FrontmatterDoc.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation

struct FrontmatterDoc: Equatable, Encodable, Sendable {
    private struct DynamicKey: CodingKey {
        // MARK: - Property
        let stringValue: String
        let intValue: Int? = nil
        
        // MARK: - Initializer
        init(_ stringValue: String) {
            self.stringValue = stringValue
        }
        
        init?(stringValue: String) {
            self.stringValue = stringValue
        }
        
        init?(intValue: Int) {
            return nil
        }
        
        // MARK: - Public
        // MARK: - Private
    }
    
    // MARK: - Property
    // No id. The file's location is the note's address, so a struct that mirrors
    // what the file carries has no field for it — and no caller can read one
    // that a raw parse never filled.
    var title: String = ""
    var priority: String = "lazy"
    var summary: String = ""
    var tags: [String] = []
    var entities: [String]? = nil
    var promotedFrom: [String]? = nil
    var source: [String] = []
    var template: String? = nil
    // Provenance, not classification: this note was planted from a seed the
    // release ships, rather than written by a person. It is the only thing that
    // tells a copy we planted apart from a note someone else wrote at the same
    // address, now that no reserved directory separates them by location.
    var seed: Bool = false
    var locked: Bool = false
    var stale: Bool = false
    var invalidatedAt: Int? = nil
    var invalidatedReason: String? = nil
    var trashedAt: Int? = nil
    var trashedReason: String? = nil
    var extra: [String: String] = [:]
    
    // MARK: - Initializer
    // MARK: - Public
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicKey.self)
        
        try container.encode(title, forKey: .init("title"))
        try container.encode(priority, forKey: .init("priority"))
        try container.encode(tags, forKey: .init("tags"))
        try container.encode(summary, forKey: .init("summary"))
        
        if let entities { try container.encode(entities, forKey: .init("entities")) }
        
        if let promotedFrom {
            try container.encode(promotedFrom, forKey: .init("promoted_from"))
        }
        
        if !source.isEmpty { try container.encode(source, forKey: .init("source")) }
        
        if let template, !template.isEmpty {
            try container.encode(template, forKey: .init("template"))
        }
        
        if seed { try container.encode(true, forKey: .init("seed")) }
        if locked { try container.encode(true, forKey: .init("locked")) }
        if stale { try container.encode(true, forKey: .init("stale")) }
        
        if let invalidatedAt, invalidatedAt != 0 {
            try container.encode(invalidatedAt, forKey: .init("invalidated_at"))
        }
        
        if let invalidatedReason, !invalidatedReason.isEmpty {
            try container.encode(invalidatedReason, forKey: .init("invalidated_reason"))
        }
        
        if let trashedAt, trashedAt != 0 {
            try container.encode(trashedAt, forKey: .init("trashed_at"))
        }
        
        if let trashedReason, !trashedReason.isEmpty {
            try container.encode(trashedReason, forKey: .init("trashed_reason"))
        }
        
        for key in extra.keys.sorted() {
            if let value = extra[key] { try container.encode(value, forKey: .init(key)) }
        }
    }
    
    // MARK: - Private
}
