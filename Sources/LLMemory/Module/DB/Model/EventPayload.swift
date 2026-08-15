//
//  EventPayload.swift
//  LLMemory
//
//  Created by JSilver on 8/16/26.
//

import Foundation

// An event's payload, in the form the column stores it. Encoding happens
// once, where the facts are known, and the value travels as text from there
// — which is why a read path can derive one and hand it to a write
// transaction across a concurrency boundary.
//
// Encoding cannot fail into the caller's lap: a trace that refuses to
// serialise must not take down the operation it traces, so an unencodable
// payload degrades to an empty object.
struct EventPayload: Sendable, Hashable {
    // MARK: - Property
    let json: String

    // MARK: - Initializer
    init(_ fields: [String: Any?]) {
        json = Self.encode(fields)
    }

    // A retrieval payload is read back by the command that produced it, so
    // the command is part of the payload rather than something callers
    // remember to put in it.
    init(command: RetrievalCommand, _ fields: [(String, Any?)]) {
        var merged: [String: Any?] = ["cmd": command.rawValue]

        for (key, value) in fields { merged[key] = value }

        json = Self.encode(merged)
    }

    // MARK: - Public
    // MARK: - Private
    private static func encode(_ fields: [String: Any?]) -> String {
        let present = fields.compactMapValues { value in value }

        guard let data = try? JSONSerialization.data(withJSONObject: present),
            let json = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }

        return json
    }
}
