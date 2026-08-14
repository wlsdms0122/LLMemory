//
//  RevalidateHandler.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation

struct RevalidateHandler: OperationHandling {
    // MARK: - Property
    let schema = OperationSchema(
        summary: "clear stale flag on a previously-invalidated note",
        fields: [
            .required("id", role: .noteId, "target note id; must currently be stale=true"),
            .required("reason", "why it's valid again; recorded in lifecycle")
        ],
        example: ##"{"op":"revalidate","id":"my-note","reason":"verified against current source"}"##
    )

    private let payload = OpPayloadCheck()

    private let frontmatter = Frontmatter()

    // MARK: - Initializer
    // MARK: - Public
    func validate(
        _ op: [String: Any],
        _ context: HandlerContext,
        _ scope: GRDBReadScope
    ) throws -> String? {
        let noteId = op["id"] as? String ?? ""

        if let rejection = try payload.checkIDKnown(noteId, context: context, scope: scope) {
            return rejection
        }

        guard let stale = try scope.run(FetchNoteStaleStateTransaction(nid: noteId)) else {
            return "unknown id: \(noteId)"
        }

        if !stale { return "note is not stale: \(noteId)" }

        return nil
    }

    func write(
        _ op: [String: Any],
        _ context: HandlerContext,
        _ scope: GRDBScope
    ) throws -> [String: Any] {
        let now = context.now
        let noteId = op["id"] as! String

        guard let path = try scope.run(FetchNotePathTransaction(nid: noteId)),
            FileManager.default.fileExists(atPath: path.path)
        else {
            throw NSError(domain: "Handlers", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "revalidate target missing: \(noteId)"
            ])
        }

        var (doc, body) = try frontmatter.parse(try String(contentsOf: path, encoding: .utf8))
        doc.stale = false
        doc.invalidatedAt = nil
        doc.invalidatedReason = nil

        try (frontmatter.dump(doc) + body).write(to: path, atomically: true, encoding: .utf8)
        try scope.run(ReindexNoteFileTransaction(path: path))
        try scope.run(SetNoteStaleTransaction(nid: noteId, stale: false))
        try scope.run(RecordNoteLifecycleEventTransaction(nid: noteId,
            kind: "revalidated",
            reason: op["reason"] as? String,
            now: now
        ))

        return ["status": "ok", "path": path.path, "ids": [noteId], "note": "revalidated"]
    }

    func touches(_ op: [String: Any], _ scope: GRDBReadScope) throws -> [URL] {
        guard let noteId = op["id"] as? String,
            let path = try scope.run(FetchNotePathTransaction(nid: noteId))
        else {
            return []
        }

        return [path]
    }

    // MARK: - Private
}
