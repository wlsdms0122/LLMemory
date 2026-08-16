//
//  JSONValue.swift
//  LLMemory
//
//  Created by JSilver on 8/16/26.
//

import Foundation

// A value JSON can carry, and nothing else. Payloads used to be built out of
// `Any`, which meant the set of things that could go in was larger than the
// set that could come out — and the gap was only discovered at write time, by
// a serializer that raises rather than throws.
//
// Integer and number are separate cases on purpose. They are one type in
// JSON's grammar but not to the readers: the shadow replay asks a payload for
// `limit` as an Int, and a limit that went out as 3.0 comes back as nothing at
// all. Whichever one a value was written as is the one it has to be read as.
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
