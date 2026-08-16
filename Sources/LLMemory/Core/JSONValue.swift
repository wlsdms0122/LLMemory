//
//  JSONValue.swift
//  LLMemory
//
//  Created by JSilver on 8/16/26.
//

import Foundation

// A value JSON can carry, and nothing else. The alternative is `Any`, where
// the set of things that can go in is larger than the set that can come out —
// and the gap is only discovered at write time, by a serializer that raises
// rather than throws.
//
// Integer and number are separate cases on purpose. They are one type in
// JSON's grammar but not to a reader that asked for an Int: a value written
// as 3 and read back as 3.0 answers nothing at all. Whichever one a value was
// written as is the one it has to be read as.
enum JSONValue: Codable, Sendable, Hashable {
    // MARK: - Property
    case string(String)
    case integer(Int)
    case number(Double)
    case bool(Bool)
    case array([JSONValue])
    case object([String: JSONValue])

    // MARK: - Initializer
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        // Ordered by how narrow the type is: an integer decoded as a double
        // is a value that stopped being an integer on the way through.
        if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .integer(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    // A list of ids or tags — the shape most payload fields already are.
    init(_ values: [String]) {
        self = .array(values.map { value in .string(value) })
    }

    // MARK: - Public
    // The reader's side of the integer/number split: a field written as one
    // is asked for as one, and a payload that carries something else answers
    // nothing rather than a number that was never meant to be an index.
    var integer: Int? {
        guard case let .integer(value) = self else { return nil }

        return value
    }

    var string: String? {
        guard case let .string(value) = self else { return nil }

        return value
    }

    // A list of ids or tags read back. A member that is not a string is not
    // one of them — the whole field is refused rather than silently thinned.
    var strings: [String]? {
        guard case let .array(values) = self else { return nil }

        return try? values.map { value in
            guard case let .string(text) = value else { throw JSONValueMismatch() }

            return text
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case let .string(value): try container.encode(value)
        case let .integer(value): try container.encode(value)
        case let .number(value): try container.encode(value)
        case let .bool(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case let .object(value): try container.encode(value)
        }
    }

    // MARK: - Private
}

// Thrown only to abandon a map that met the wrong shape — the caller sees a
// nil field, which is the same answer as a field that was never written.
private struct JSONValueMismatch: Error { }

// The literal conformances are what keep a payload readable as a dictionary
// literal — the alternative is wrapping every constant at every call site,
// which is noise around the one thing the reader came to see.
extension JSONValue: ExpressibleByStringLiteral {
    init(stringLiteral value: String) {
        self = .string(value)
    }
}

extension JSONValue: ExpressibleByIntegerLiteral {
    init(integerLiteral value: Int) {
        self = .integer(value)
    }
}

extension JSONValue: ExpressibleByFloatLiteral {
    init(floatLiteral value: Double) {
        self = .number(value)
    }
}

extension JSONValue: ExpressibleByBooleanLiteral {
    init(booleanLiteral value: Bool) {
        self = .bool(value)
    }
}

extension JSONValue: ExpressibleByArrayLiteral {
    init(arrayLiteral elements: JSONValue...) {
        self = .array(elements)
    }
}

extension JSONValue: ExpressibleByDictionaryLiteral {
    init(dictionaryLiteral elements: (String, JSONValue)...) {
        self = .object(Dictionary(elements) { _, last in last })
    }
}
