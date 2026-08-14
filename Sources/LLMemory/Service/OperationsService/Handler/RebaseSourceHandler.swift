//
//  RebaseSourceHandler.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation

struct RebaseSourceHandler: OperationHandling {
    // MARK: - Property
    let schema = OperationSchema(
        summary: "assert the note was verified against its current source files (no file edit): re-baseline the source fingerprint and clear source_stale",
        fields: [
            .required("id", role: .noteId, "target note id; must have a drift-tracked source"),
            .required("reason", "how the sources were verified/reconciled (recorded in note_lifecycle_events)")
        ],
        example: ##"{"op":"rebase_source","id":"my-note","reason":"note updated to reflect the reworked source file"}"##
    )

    // MARK: - Initializer
    // MARK: - Public
    func validate(
        _ op: [String: Any],
        _ context: HandlerContext,
        _ scope: GRDBReadScope
    ) throws -> String? {
        let noteId = op["id"] as? String ?? ""

        if let rejection = try Handlers.checkIDKnown(noteId, context: context, scope: scope) {
            return rejection
        }

        if !(try scope.run(NoteSourceTrackedTransaction(nid: noteId))) {
            return "note has no drift-tracked source: \(noteId)"
        }

        return nil
    }

    func write(
        _ op: [String: Any],
        _ context: HandlerContext,
        _ scope: GRDBScope
    ) throws -> [String: Any] {
        let now = context.now
        let noteId = op["id"] as! String

        try scope.run(RebaseNoteSourceTransaction(
            noteId: noteId,
            paths: try scope.run(FetchNoteSourcePathsTransaction(noteId: noteId)),
            now: now
        ))
        try scope.run(RecordNoteLifecycleEventTransaction(nid: noteId,
            kind: "source_rebased",
            reason: op["reason"] as? String,
            now: now
        ))

        return ["status": "ok", "ids": [noteId], "note": "source re-baselined"]
    }

    // MARK: - Private
}
