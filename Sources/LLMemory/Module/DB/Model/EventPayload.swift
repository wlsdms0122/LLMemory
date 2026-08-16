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
    init(_ fields: [String: JSONValue?]) {
        json = Self.encode(fields)
    }

    // A retrieval payload is read back by the command that produced it, so
    // the command is part of the payload rather than something callers
    // remember to put in it.
    init(command: RetrievalCommand, _ fields: [String: JSONValue?]) {
        self.init(fields.merging(["cmd": .string(command.rawValue)]) { _, command in command })
    }

    // MARK: - Public
    // MARK: - Private
    private static func encode(_ fields: [String: JSONValue?]) -> String {
        let encoder = JSONEncoder()

        // Sorted so the same facts produce the same row. The log is read by
        // eye as often as by query, and two payloads that differ only in the
        // order Swift hashed their keys read as two different payloads.
        encoder.outputFormatting = .sortedKeys

        // JSONValue leaves exactly one way to fail: a double JSON has no
        // spelling for. The encoder throws on it — which is the whole reason
        // the payload is built out of a closed type rather than Any, where the
        // same value reached a serializer that raises and took the process
        // down with the trace it was only supposed to record.
        guard let data = try? encoder.encode(fields.compactMapValues { value in value }),
            let json = String(data: data, encoding: .utf8)
        else {
            return failed(command: fields["cmd"] ?? nil)
        }

        return json
    }

    // The command survives where there was one: it is the field the log's
    // readers select on, so keeping it means the loss is visible from the
    // same query that would have found the event intact.
    private static func failed(command: JSONValue?) -> String {
        guard case let .string(command) = command else {
            return #"{"payload_encode_failed":true}"#
        }

        return #"{"cmd":"\#(command)","payload_encode_failed":true}"#
    }
}
