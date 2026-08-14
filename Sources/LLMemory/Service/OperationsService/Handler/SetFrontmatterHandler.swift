//
//  SetFrontmatterHandler.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation

struct SetFrontmatterHandler: OperationHandling {
    // MARK: - Property
    let schema = OperationSchema(
        summary: "merge frontmatter fields (any field the note owns)",
        fields: [
            .required("id", role: .noteId, "target note id"),
            .required("fields", "non-empty dict. Known: title|summary|tags|priority|source|promoted_from|entities. Any other key is a custom field (scalar value, projected to note_extra); null removes it. Rejected: id/template/locked/stale/invalidated_*/trashed_* — each has its own op")
        ],
        example: ##"{"op":"set_frontmatter","id":"my-note","fields":{"summary":"updated summary","affect":"high"}}"##
    )

    private let composer = NoteComposer()
    private let payload = OpPayloadCheck()
    private let writeEffects = NoteWriteEffects()

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

        guard let fields = op["fields"] as? [String: Any], !fields.isEmpty else {
            return "fields must be non-empty dict"
        }

        if let tags = fields["tags"] {
            guard let array = tags as? [Any], !array.isEmpty else {
                return "tags must be non-empty list"
            }
        }

        if let priority = fields["priority"] as? String,
            !OpVocabulary.validPriority.contains(priority) {
            return "invalid priority: \(priority)"
        }

        do {
            var probe = FrontmatterDoc()

            if let path = try scope.run(FetchNotePathTransaction(nid: noteId)),
                let read = try Notes.readNoteIfPresent(at: path) {
                probe = read.doc
            }

            try composer.mergeFields(&probe, fields)
        } catch {
            return "\(error)"
        }

        return nil
    }

    func write(
        _ op: [String: Any],
        _ context: HandlerContext,
        _ scope: GRDBScope
    ) throws -> [String: Any] {
        let noteId = op["id"] as! String

        guard let path = try scope.run(FetchNotePathTransaction(nid: noteId)),
            FileManager.default.fileExists(atPath: path.path)
        else {
            throw NSError(domain: "Handlers", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "note file missing: \(noteId)"
            ])
        }

        let raw = try String(contentsOf: path, encoding: .utf8)
        var (doc, body) = try Frontmatter.parse(raw)
        let fields = op["fields"] as! [String: Any]

        try composer.mergeFields(&doc, fields)
        try (Frontmatter.dump(doc) + body).write(to: path, atomically: true, encoding: .utf8)
        try scope.run(ReindexNoteFileTransaction(path: path))

        let now = context.now

        try scope.run(StampNoteLifecycleTransaction(nid: noteId, now: now, isNew: false))

        let keys = fields.keys.sorted().joined(separator: ",")

        try writeEffects.recordEdit(scope, nid: noteId, opLabel: "set_frontmatter/\(keys)", now: now)

        return [
            "status": "ok",
            "path": path.path,
            "ids": [noteId],
            "note": "updated fields: \(fields.keys.sorted())"
        ]
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
