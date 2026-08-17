//
//  LinkLineageHandler.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct LinkLineageHandler: OperationHandling {
    // MARK: - Property
    let schema = OperationSchema(
        summary: "record a lineage fact between two notes (promoted_to / supersedes / merge_ancestor) "
        + "at full weight, decay-exempt. Use when a note was extracted from, replaces, or "
        + "descends from another — not for semantic association (that is propose_link).",
        fields: [
            .required("src", role: .noteId, "subject of the relation — read the edge as the sentence "
                + "`src <kind> dst`, so which note goes here depends on the kind (see below)"),
            .required("dst", role: .noteId, "object of the relation"),
            .required("kind", "'promoted_to' (src=origin journal, dst=the note extracted from it) "
                + "| 'supersedes' (src=the replacement, dst=what it replaces) "
                + "| 'merge_ancestor' (src=surviving note, dst=the note merged away)"),
            .optional("reason", "why this lineage holds; recorded on src's lifecycle")
        ],
        example: ##"{"op":"link_lineage","src":"bk-5262-rc1-260524","dst":"deploy-approval-policy","kind":"promoted_to","reason":"회차 반복 패턴을 원리로 추출"}"##
    )
    
    private let noteExistence = NoteExistence()
    
    // MARK: - Initializer
    // MARK: - Public
    func validate(
        _ op: [String: Any],
        _ context: HandlerContext,
        _ db: Database
    ) throws -> String? {
        let rawKind = op["kind"] as? String ?? ""
        let lineage = LinkKind.rawValues { kind in kind.isLineage }
        
        guard lineage.contains(rawKind) else {
            return "invalid lineage kind: \(rawKind) (expected \(lineage.sorted().joined(separator: " | ")))"
        }
        
        let src = op["src"] as? String ?? ""
        let dst = op["dst"] as? String ?? ""
        
        if src == dst { return "src and dst must differ: \(src)" }
        
        if let rejection = try noteExistence.rejectionForUnknown(src, context: context, db: db) {
            return rejection
        }
        
        return try noteExistence.rejectionForUnknown(dst, context: context, db: db)
    }
    
    func write(
        _ op: [String: Any],
        _ context: HandlerContext,
        _ db: Database
    ) throws -> [String: Any] {
        let now = context.now
        let src = op["src"] as! String
        let dst = op["dst"] as! String
        // validate() refused every spelling that is not a lineage kind.
        let kind = LinkKind(rawValue: op["kind"] as! String)!
        
        try InsertLineageLinkOperation(src: src, dst: dst, kind: kind, now: now).execute(db)
        
        let reason = op["reason"] as? String
        
        try RecordNoteLifecycleEventOperation(
            nid: src,
            kind: kind.rawValue,
            reason: reason,
            now: now
        ).execute(db)
        
        return [
            "status": "ok",
            "ids": [src, dst],
            "note": "recorded \(kind.rawValue): \(src) → \(dst)"
        ]
    }
    
    // MARK: - Private
}
