//
//  NoteComposer.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation

// Builds what a new or edited note is made of: the body a create_note lands
// (scaffolded from its template frame when it declares one), and the custom
// frontmatter fields an op carries that the note, not the op, is meant to keep.
struct NoteComposer {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Public
    func composeCreateBody(_ op: [String: Any], _ scope: GRDBReadScope) throws -> String {
        let raw = op["content"] as? String ?? ""
        var content = String(raw.reversed().drop(while: { character in character.isWhitespace }).reversed())
        let templateId = (op["template"] as? String).flatMap { value in value.isEmpty ? nil : value }
        
        if let templateId, content.isEmpty,
            let frame = try scope.run(LoadTemplateFrameTransaction(templateId: templateId)) {
            content = Template.scaffold(frame)
        }
        
        return content + "\n"
    }

    func mergeFields(_ doc: inout FrontmatterDoc, _ fields: [String: Any]) throws {
        func string(_ key: String, _ value: Any) throws -> String {
            guard let string = value as? String else {
                throw FieldTypeError(field: key, expected: "string", got: value)
            }
            
            return string
        }
        
        func list(_ key: String, _ value: Any) throws -> [String] {
            guard let array = value as? [Any] else {
                throw FieldTypeError(field: key, expected: "list of strings", got: value)
            }
            
            guard array.count == array.compactMap({ element in element as? String }).count else {
                throw FieldTypeError(field: key, expected: "list of strings", got: value)
            }
            
            return array.compactMap { element in element as? String }
        }

        // A custom field is one frontmatter line, so its value must be a scalar that
        // survives the `key: value` round trip — no newlines, no nesting.
        func scalar(_ key: String, _ value: Any) throws -> String {
            let text: String

            switch value {
            case let bool as Bool:
                text = bool ? "true" : "false"

            case let int as Int:
                text = String(int)

            case let double as Double:
                text = String(double)

            case let string as String:
                text = string

            default:
                throw FieldTypeError(field: key, expected: "string, number or bool", got: value)
            }

            let trimmed = text.trimmingCharacters(in: .whitespaces)

            guard !trimmed.isEmpty, !trimmed.contains(where: \.isNewline) else {
                throw FieldTypeError(
                    field: key,
                    expected: "a non-empty single-line value (null removes the field)",
                    got: value
                )
            }

            return trimmed
        }

        for (key, value) in fields {
            switch key {
            case "title":
                doc.title = try string(key, value)

            case "summary":
                doc.summary = try string(key, value)

            case "tags":
                doc.tags = try list(key, value)

            case "priority":
                doc.priority = try string(key, value)

            case "source":
                doc.source = try Frontmatter.decodeSource(value)

            case "promoted_from":
                let promotedFrom = try list(key, value)
                doc.promotedFrom = promotedFrom.isEmpty ? nil : promotedFrom

            case "entities":
                let entities = try list(key, value)
                doc.entities = entities.isEmpty ? nil : entities

            default:
                guard OpVocabulary.frontmatterReserved.contains(key) == false else {
                    throw ReservedFieldError(field: key)
                }

                guard OpVocabulary.extraKeyRegex.firstMatch(
                    in: key,
                    range: NSRange(location: 0, length: (key as NSString).length)
                ) != nil else {
                    throw FieldTypeError(
                        field: key,
                        expected: "a frontmatter key ([A-Za-z_]\\w*)",
                        got: value
                    )
                }

                if value is NSNull {
                    doc.extra.removeValue(forKey: key)
                } else {
                    doc.extra[key] = try scalar(key, value)
                }
            }
        }
    }

    // MARK: - Private
}
