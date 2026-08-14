//
//  Frontmatter.swift
//  LLMemory
//
//  Created by JSilver on 8/7/26.
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

enum Frontmatter {
    // MARK: - Property
    // The keys parse() recognises. Everything else is a custom field — this list
    // exists so a near-miss ('summry') can be told apart from an intended one.
    static let knownFields: [String] = [
        "title", "priority", "summary", "tags", "entities",
        "promoted_from", "source", "template", "seed", "locked", "stale",
        "invalidated_at", "invalidated_reason", "trashed_at", "trashed_reason"
    ]

    private static let frontmatterRegex: NSRegularExpression = try! NSRegularExpression(
        pattern: #"\A---\n(.*?)\n---\n+(.*)"#,
        options: [.dotMatchesLineSeparators]
    )
    
    private static let fieldRegex: NSRegularExpression = try! NSRegularExpression(
        pattern: #"^(\w+):\s*(.+?)\s*$"#,
        options: []
    )
    
    // MARK: - Initializer
    // MARK: - Public
    static func parse(_ text: String) throws -> (FrontmatterDoc, String) {
        let nsText = text as NSString
        
        guard let match = frontmatterRegex.firstMatch(
            in: text,
            range: NSRange(location: 0, length: nsText.length)
        ) else {
            throw FrontmatterError.missing
        }
        
        let frontmatterText = nsText.substring(with: match.range(at: 1))
        let body = nsText.substring(with: match.range(at: 2))
        var doc = FrontmatterDoc()
        
        for line in frontmatterText.unicodeLines() {
            let nsLine = line as NSString
            
            guard let fieldMatch = fieldRegex.firstMatch(
                in: line,
                range: NSRange(location: 0, length: nsLine.length)
            ) else {
                if line.trimmingCharacters(in: .whitespaces).isEmpty { continue }
                
                throw FrontmatterError.malformedLine(line: line)
            }
            
            let key = nsLine.substring(with: fieldMatch.range(at: 1))
            let value = nsLine.substring(with: fieldMatch.range(at: 2))
                .trimmingCharacters(in: .whitespaces)
            
            switch key {
            // A leftover from when the address was written down twice. Ignored
            // rather than kept as a custom field, and lint says it is there.
            case "id":
                continue
            
            case "title":
                doc.title = value
            
            case "priority":
                doc.priority = value
            
            case "summary":
                doc.summary = value
            
            case "tags", "entities", "promoted_from":
                guard value.hasPrefix("["), value.hasSuffix("]") else {
                    throw FrontmatterError.malformedList(key: key, value: value)
                }
                
                let items = splitList(String(value.dropFirst().dropLast()))
                
                switch key {
                case "tags":
                    doc.tags = items
                
                case "entities":
                    doc.entities = items
                
                default:
                    doc.promotedFrom = items
                }
            
            case "source":
                if value.hasPrefix("[") {
                    guard let data = value.data(using: .utf8),
                        let parsed = try? JSONSerialization.jsonObject(with: data, options: []),
                        let array = parsed as? [Any]
                    else {
                        throw FrontmatterError.malformedSource(value: value)
                    }
                    
                    doc.source = try decodeSource(array)
                } else {
                    doc.source = value.isEmpty ? [] : try decodeSource(value)
                }
            
            case "template":
                doc.template = value.isEmpty ? nil : value
            
            case "seed":
                doc.seed = coerceBool(value)

            case "locked":
                doc.locked = coerceBool(value)
            
            case "stale":
                doc.stale = coerceBool(value)
            
            case "invalidated_at":
                doc.invalidatedAt = coerceInt(value)
            
            case "invalidated_reason":
                doc.invalidatedReason = value
            
            case "trashed_at":
                doc.trashedAt = coerceInt(value)
            
            case "trashed_reason":
                doc.trashedReason = value
            
            default:
                doc.extra[key] = value
            }
        }
        
        return (doc, body)
    }
    
    static func dump(_ doc: FrontmatterDoc) -> String {
        var lines: [String] = []
        
        lines.append("---")
        lines.append("title: \(doc.title)")
        lines.append("priority: \(doc.priority)")
        lines.append("tags: [" + doc.tags.joined(separator: ", ") + "]")
        lines.append("summary: \(doc.summary)")
        
        if let entities = doc.entities, !entities.isEmpty {
            lines.append("entities: [" + entities.joined(separator: ", ") + "]")
        }
        
        if let promotedFrom = doc.promotedFrom, !promotedFrom.isEmpty {
            lines.append("promoted_from: [" + promotedFrom.joined(separator: ", ") + "]")
        }
        
        if !doc.source.isEmpty {
            let data = (try? JSONSerialization.data(withJSONObject: doc.source, options: []))
                ?? Data()
            let json = String(data: data, encoding: .utf8) ?? "[]"
            lines.append("source: \(json)")
        }
        
        if let template = doc.template, !template.isEmpty {
            lines.append("template: \(template)")
        }
        
        if doc.seed {
            lines.append("seed: true")
        }

        if doc.locked {
            lines.append("locked: true")
        }
        
        if doc.stale {
            lines.append("stale: true")
        }
        
        if let invalidatedAt = doc.invalidatedAt, invalidatedAt != 0 {
            lines.append("invalidated_at: \(invalidatedAt)")
        }
        
        if let invalidatedReason = doc.invalidatedReason, !invalidatedReason.isEmpty {
            lines.append("invalidated_reason: \(invalidatedReason)")
        }
        
        if let trashedAt = doc.trashedAt, trashedAt != 0 {
            lines.append("trashed_at: \(trashedAt)")
        }
        
        if let trashedReason = doc.trashedReason, !trashedReason.isEmpty {
            lines.append("trashed_reason: \(trashedReason)")
        }
        
        for key in doc.extra.keys.sorted() {
            if let value = doc.extra[key] { lines.append("\(key): \(value)") }
        }
        
        lines.append("---")
        lines.append("")
        lines.append("")
        
        return lines.joined(separator: "\n")
    }
    
    static func decodeSource(_ raw: Any) throws -> [String] {
        if let array = raw as? [Any] {
            return try array.map { element in try decodeSourceRef(element, in: raw) }
        }
        
        return [try decodeSourceRef(raw, in: raw)]
    }
    
    // MARK: - Private
    private static func decodeSourceRef(_ element: Any, in whole: Any) throws -> String {
        if let path = element as? String, !path.isEmpty { return path }
        
        if let dictionary = element as? [String: Any],
            let path = dictionary["path"] as? String,
            !path.isEmpty {
            return path
        }
        
        throw FrontmatterError.malformedSourceElement(
            value: String(describing: whole),
            element: String(describing: element)
        )
    }
    
    private static func splitList(_ inner: String) -> [String] {
        inner.split(separator: ",")
            .map { item in item.trimmingCharacters(in: .whitespaces) }
            .filter { item in !item.isEmpty }
    }
    
    private static func coerceBool(_ value: String) -> Bool {
        let normalized = value.trimmingCharacters(in: .whitespaces).lowercased()
        
        return normalized == "true" || normalized == "1" || normalized == "yes"
    }
    
    private static func coerceInt(_ value: String) -> Int? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        
        return trimmed.isEmpty ? nil : Int(trimmed)
    }
}

enum FrontmatterError: Error, CustomStringConvertible, Equatable {
    case missing
    case malformedList(key: String, value: String)
    case malformedSource(value: String)
    case malformedSourceElement(value: String, element: String)
    case malformedLine(line: String)
    
    var description: String {
        switch self {
        case .missing:
            return "frontmatter missing"
        
        case .malformedList(let key, let value):
            return "frontmatter list field '\(key)' must be bracketed (e.g. \(key): [a, b]) — got: \(value)"
        
        case .malformedSource(let value):
            return "frontmatter 'source' bracketed form must be a JSON array (e.g. source: [\"/abs/a.swift\"]) — got: \(value)"
        
        case .malformedSourceElement(let value, let element):
            return "frontmatter 'source' element must be a non-empty string or {\"path\": \"...\"} — got \(element) in: \(value)"
        
        case .malformedLine(let line):
            return "frontmatter line is not single-line 'key: value' form: \(line)"
        }
    }
}
