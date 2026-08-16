//
//  Frontmatter.swift
//  LLMemory
//
//  Created by JSilver on 8/7/26.
//

import Foundation

struct Frontmatter: Sendable {
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
    func parse(_ text: String) throws -> (FrontmatterDocument, String) {
        let nsText = text as NSString
        
        guard let match = Self.frontmatterRegex.firstMatch(
            in: text,
            range: NSRange(location: 0, length: nsText.length)
        ) else {
            throw FrontmatterError.missing
        }
        
        let frontmatterText = nsText.substring(with: match.range(at: 1))
        let body = nsText.substring(with: match.range(at: 2))
        var doc = FrontmatterDocument()
        
        for line in frontmatterText.unicodeLines() {
            let nsLine = line as NSString
            
            guard let fieldMatch = Self.fieldRegex.firstMatch(
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
    
    func dump(_ doc: FrontmatterDocument) -> String {
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
    
    func decodeSource(_ raw: Any) throws -> [String] {
        if let array = raw as? [Any] {
            return try array.map { element in try decodeSourceRef(element, in: raw) }
        }
        
        return [try decodeSourceRef(raw, in: raw)]
    }
    
    // MARK: - Private
    private func decodeSourceRef(_ element: Any, in whole: Any) throws -> String {
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
    
    private func splitList(_ inner: String) -> [String] {
        inner.split(separator: ",")
            .map { item in item.trimmingCharacters(in: .whitespaces) }
            .filter { item in !item.isEmpty }
    }
    
    private func coerceBool(_ value: String) -> Bool {
        let normalized = value.trimmingCharacters(in: .whitespaces).lowercased()
        
        return normalized == "true" || normalized == "1" || normalized == "yes"
    }
    
    private func coerceInt(_ value: String) -> Int? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        
        return trimmed.isEmpty ? nil : Int(trimmed)
    }
}
