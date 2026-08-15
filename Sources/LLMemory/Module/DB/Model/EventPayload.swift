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
// serialise must not take down the operation it traces. What it must not do
// either is arrive looking like a payload that carried nothing — the readers
// downstream count these rows, and a row that lost its contents has to be
// countable as that.
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
    init(command: RetrievalCommand, _ fields: [String: Any?]) {
        self.init(fields.merging(["cmd": command.rawValue]) { _, command in command })
    }

    // MARK: - Public
    // MARK: - Private
    private static func encode(_ fields: [String: Any?]) -> String {
        let present = fields.compactMapValues { value in value }

        // isValidJSONObject before data(withJSONObject:), not instead of it:
        // the serializer raises on an invalid object rather than throwing, so
        // a `try?` around it catches nothing and the process goes down with
        // the trace it was only supposed to record.
        guard JSONSerialization.isValidJSONObject(present),
            let data = try? JSONSerialization.data(withJSONObject: present),
            let json = String(data: data, encoding: .utf8)
        else {
            return failed(command: present["cmd"] as? String)
        }

        return json
    }

    // The command survives where there was one: it is the field the log's
    // readers select on, so keeping it means the loss is visible from the
    // same query that would have found the event intact.
    private static func failed(command: String?) -> String {
        guard let command else { return #"{"payload_encode_failed":true}"# }

        return #"{"cmd":"\#(command)","payload_encode_failed":true}"#
    }
}
