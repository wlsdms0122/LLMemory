//
//  EventLogTests.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/16/26.
//

import Testing
import Foundation
import GRDB
@testable import LLMemory

// The event log is written by one side and read by another, and the two only
// meet in the stored text. These close that loop: what a write puts in the
// row has to be what a read looks for.
@Suite("EventLog Tests")
struct EventLogTests {
    // MARK: - Property
    private let home: MemoryHome

    // MARK: - Initializer
    init() throws {
        home = try MemoryHome()
    }

    // MARK: - Test
    @Test("a retrieval written through the transaction is one the log reader finds")
    func writtenKindIsTheKindRead() throws {
        try home.write { database in
            try RecordEventTransaction(
                kind: .retrieval,
                payload: EventPayload(command: .search, ["query": "quokka", "hit_ids": JSONValue(["n1"])]),
                ts: 1_000
            )
                .perform(database)
        }

        let logged = try home.read { database in
            try FetchLoggedRetrievalQueriesTransaction(limit: 10).perform(database)
        }

        #expect(logged.count == 1)
        #expect(logged.first?.text == "quokka")
    }

    @Test("a command this binary does not know is skipped, not replayed as something else")
    func unknownCommandIsSkipped() throws {
        try home.write { database in
            try database.execute(
                sql: "INSERT INTO events (ts, kind, session_id, payload) VALUES (?, ?, NULL, ?)",
                arguments: [1_000, EventKind.retrieval.rawValue,
                    #"{"cmd":"telepathy","query":"quokka"}"#]
            )
        }

        let logged = try home.read { database in
            try FetchLoggedRetrievalQueriesTransaction(limit: 10).perform(database)
        }

        #expect(logged.isEmpty)
    }

    @Test("only search carries tags and a limit — related has none to carry")
    func replayCarriesOnlyItsOwnInputs() throws {
        try home.write { database in
            try RecordEventTransaction(
                kind: .retrieval,
                payload: EventPayload(
                    command: .search, ["query": "a", "tags": JSONValue(["swift"]), "limit": 3]),
                ts: 1_000
            )
                .perform(database)
            try RecordEventTransaction(
                kind: .retrieval,
                payload: EventPayload(command: .related, ["text": "b"]),
                ts: 1_001
            )
                .perform(database)
        }

        let logged = try home.read { database in
            try FetchLoggedRetrievalQueriesTransaction(limit: 10).perform(database)
        }
        let replays = logged.map { query in query.replay }

        #expect(replays.count == 2)
        #expect(replays.contains { replay in
            if case let .search(tags, limit) = replay { return tags == ["swift"] && limit == 3 }

            return false
        })
        #expect(replays.contains { replay in
            if case .related = replay { return true }

            return false
        })
    }

    @Test("a field with nothing in it is absent from the payload, not present as null")
    func absentFieldsAreNotWritten() {
        let payload = EventPayload(["kept": "yes", "dropped": nil])
        let decoded = try? JSONSerialization.jsonObject(
            with: Data(payload.json.utf8)) as? [String: Any]

        #expect(decoded?.keys.sorted() == ["kept"])
    }

    @Test("an integer stays one across the column — a limit read back as 3.0 is a limit lost")
    func integersDoNotArriveAsDoubles() {
        let payload = EventPayload(["limit": 3, "ratio": 0.5])
        let decoded = try? JSONSerialization.jsonObject(
            with: Data(payload.json.utf8)) as? [String: Any]

        #expect(payload.json.contains("\"limit\":3,"), "got \(payload.json)")
        #expect(decoded?["limit"] as? Int == 3, "the shadow replay reads this field as an Int")
        #expect(decoded?["ratio"] as? Double == 0.5)
    }

    @Test("a payload that could not be encoded says so instead of arriving empty")
    func failedEncodeIsDistinguishableFromEmpty() {
        let lost = EventPayload(["count": .number(.nan)])

        #expect(lost.json != "{}")
        #expect(lost.json.contains("payload_encode_failed"))
        #expect(EventPayload([:]).json == "{}", "carrying nothing is not the same as losing it")
    }

    @Test("the command survives an encoding failure — it is what the readers select on")
    func failedEncodeKeepsItsCommand() {
        let lost = EventPayload(command: .search, ["count": .number(.nan)])
        let decoded = try? JSONSerialization.jsonObject(with: Data(lost.json.utf8)) as? [String: Any]

        #expect(decoded?["cmd"] as? String == RetrievalCommand.search.rawValue)
        #expect(decoded?["payload_encode_failed"] as? Bool == true)
    }

    // MARK: - Private
}
