//
//  RelocateSectionHandler.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation

struct RelocateSectionHandler: OperationHandling {
    // MARK: - Property
    let schema = OperationSchema(
        summary: "move a section from one note to another (extract from src + insert into dst)",
        fields: [
            .required("from_id", role: .noteId, "source note id"),
            .required("to_id", role: .noteId, "destination note id (must differ from from_id)"),
            .required("section", ###"section path with heading marker, e.g. "## 제목""###),
            .optional("position", ###"insertion target in dst: "end" (default) | "start" | {"after": "## path"} | {"before": "## path"}"###)
        ],
        example: ###"{"op":"relocate_section","from_id":"src-note","to_id":"dst-note","section":"## 부록","position":"end"}"###
    )

    // MARK: - Initializer
    // MARK: - Public
    func validate(
        _ op: [String: Any],
        _ context: HandlerContext,
        _ scope: GRDBReadScope
    ) throws -> String? {
        let fromId = op["from_id"] as? String ?? ""
        let toId = op["to_id"] as? String ?? ""

        if fromId == toId { return "from_id and to_id must differ" }

        if let rejection = try Handlers.checkIDKnown(fromId, context: context, scope: scope) {
            return rejection
        }

        if let rejection = try Handlers.checkIDKnown(toId, context: context, scope: scope) {
            return rejection
        }

        do {
            _ = try SectionEdit.parsePath(op["section"] as? String ?? "")
        } catch {
            return "invalid section path: \(error)"
        }

        let position = op["position"] ?? "end"

        if let anchor = position as? String, anchor == "end" || anchor == "start" {
            return nil
        }

        if let anchor = position as? [String: Any] {
            if anchor["after"] != nil || anchor["before"] != nil { return nil }

            return "position dict requires after or before"
        }

        return "position must be 'end'/'start' or {after|before: <path>}"
    }

    func write(
        _ op: [String: Any],
        _ context: HandlerContext,
        _ scope: GRDBScope
    ) throws -> [String: Any] {
        let fromId = op["from_id"] as! String
        let toId = op["to_id"] as! String

        guard let srcPath = try scope.run(FetchNotePathTransaction(nid: fromId)),
            FileManager.default.fileExists(atPath: srcPath.path),
            let dstPath = try scope.run(FetchNotePathTransaction(nid: toId)),
            FileManager.default.fileExists(atPath: dstPath.path)
        else {
            throw NSError(domain: "Handlers", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "note missing"
            ])
        }

        let (srcDoc, srcBody) = try Frontmatter.parse(
            try String(contentsOf: srcPath, encoding: .utf8)
        )
        let (dstDoc, dstBody) = try Frontmatter.parse(
            try String(contentsOf: dstPath, encoding: .utf8)
        )
        let sectionPath = try SectionEdit.parsePath(op["section"] as! String)
        let (extracted, srcRemaining) = try SectionEdit.extract(srcBody, paths: [sectionPath])
        let position = op["position"] ?? "end"
        let newDst: String

        if let anchor = position as? String, anchor == "end" {
            newDst = try SectionEdit.insert(
                dstBody,
                newSectionText: extracted,
                anchor: .atEnd
            )
        } else if let anchor = position as? String, anchor == "start" {
            newDst = extracted + (extracted.hasSuffix("\n") ? "" : "\n") + dstBody
        } else if let anchor = position as? [String: Any],
            let after = anchor["after"] as? String {
            newDst = try SectionEdit.insert(
                dstBody,
                newSectionText: extracted,
                anchor: .after(try SectionEdit.parsePath(after))
            )
        } else if let anchor = position as? [String: Any],
            let before = anchor["before"] as? String {
            newDst = try SectionEdit.insert(
                dstBody,
                newSectionText: extracted,
                anchor: .before(try SectionEdit.parsePath(before))
            )
        } else {
            throw NSError(domain: "Handlers", code: 2)
        }

        try (Frontmatter.dump(srcDoc) + srcRemaining).write(
            to: srcPath,
            atomically: true,
            encoding: .utf8
        )
        try (Frontmatter.dump(dstDoc) + newDst).write(
            to: dstPath,
            atomically: true,
            encoding: .utf8
        )
        try scope.run(ReindexNoteFileTransaction(path: srcPath))
        try scope.run(ReindexNoteFileTransaction(path: dstPath))

        let now = context.now

        try scope.run(StampNoteLifecycleTransaction(nid: fromId, now: now, isNew: false))
        try scope.run(StampNoteLifecycleTransaction(nid: toId, now: now, isNew: false))
        try Handlers.recordEdit(
            scope,
            nid: fromId,
            opLabel: "relocate_section/from→\(toId)",
            now: now
        )
        try Handlers.recordEdit(
            scope,
            nid: toId,
            opLabel: "relocate_section/from←\(fromId)",
            now: now
        )

        return [
            "status": "ok",
            "paths": [srcPath.path, dstPath.path],
            "ids": [fromId, toId],
            "note": "relocated section to \(toId)"
        ]
    }

    func touches(_ op: [String: Any], _ scope: GRDBReadScope) throws -> [URL] {
        var paths: [URL] = []

        if let fromId = op["from_id"] as? String,
            let path = try scope.run(FetchNotePathTransaction(nid: fromId)) {
            paths.append(path)
        }

        if let toId = op["to_id"] as? String, let path = try scope.run(FetchNotePathTransaction(nid: toId)) {
            paths.append(path)
        }

        return paths
    }

    // MARK: - Private
}
