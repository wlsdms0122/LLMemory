//
//  OpPayloadCheck.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation

// The checks every op runs against its own payload before anything is
// written: what the schema did not declare, whether a required field is
// actually there, and whether an id names a note that exists — counting the
// ones this batch is about to create, since a batch is one transaction.
struct OpPayloadCheck {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Initializer
    // MARK: - Public
    // Whatever an op carries that its own schema does not name. For the ops that
    // author a note that is a custom frontmatter field — the caller means it for
    // the note, not for the op, and the note is where it belongs.
    func customFields(
        of op: [String: Any],
        declaredBy schema: OperationSchema
    ) -> [String: Any] {
        let declared = Set(schema.fields.map(\.name)).union(["op", "rationale"])

        return op.filter { entry in !declared.contains(entry.key) }
    }

    func existingState(_ scope: GRDBReadScope) throws -> ExistingState {
        ExistingState(ids: try scope.run(FetchNoteIdsTransaction()))
    }

    func checkRequired(_ op: [String: Any], fields: [String]) -> String? {
        for field in fields {
            if op[field] == nil { return "missing/empty field: \(field)" }
            
            if let value = op[field] as? String, value.isEmpty {
                return "missing/empty field: \(field)"
            }
            
            if op[field] is NSNull { return "missing/empty field: \(field)" }
        }
        
        return nil
    }

    func asDouble(_ raw: Any) -> Double? {
        if raw is Bool { return nil }
        if let double = raw as? Double { return double }
        if let int = raw as? Int { return Double(int) }
        if let number = raw as? NSNumber { return number.doubleValue }
        
        return nil
    }

    func checkIDKnown(
        _ nid: String,
        context: HandlerContext,
        scope: GRDBReadScope
    ) throws -> String? {
        if context.inFlightIds.contains(nid) { return nil }
        if try scope.run(NoteExistsTransaction(nid: nid)) { return nil }
        
        return "unknown id: \(nid)"
    }

    // MARK: - Private
}
