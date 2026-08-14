//
//  DismissCandidateHandler.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation

struct DismissCandidateHandler: OperationHandling {
    // MARK: - Property
    let schema = OperationSchema(
        summary: "record a *keep* decision for a consolidation candidate — \"reviewed, leave this note as-is\". "
        + "Habituation: the candidate stops re-surfacing until the note's shape diverges past an accumulating "
        + "threshold (each dismissal deepens it) or a corpus-wide reorg reopens it. No file edit; affects only "
        + "the candidate channel, never retrieval.",
        fields: [
            .required("id", unless: "target", role: .noteId, "target note id (note-scope findings)"),
            .optional("target", "for a corpus-scope lint warn (`query lint` printed scope=corpus): the "
                + "`subject` it reported, e.g. `tag-pair:금리|금융`. Mutually exclusive with `id` — "
                + "a corpus fact belongs to no note, so it is not addressable by one."),
            .required("kind", "`split`, or `lint:<code>` for a lint warn you reviewed and are keeping "
                + "(e.g. lint:dangling-note-ref). Errors are not dismissible."),
            .optional("finding", "for a lint kind: the finding you reviewed — the message, or any "
                + "substring that picks it out. Required when the target carries more than one "
                + "finding of that code, so a keep-decision answers one judgment instead of "
                + "silencing the whole code on that target."),
            .optional("reason", "why it's being kept (recorded for audit + shown if it re-surfaces)")
        ],
        example: ##"{"op":"dismiss_candidate","id":"my-note","kind":"split","reason":"한 응집 주제 — 크기는 분할 사유 아님"}"##
    )
    
    let lint: any LintScanning
    
    private let noteExistence = NoteExistence()
    
    private let dismissalPolicy = Dismissals()
    
    // MARK: - Initializer
    // MARK: - Public
    func validate(
        _ op: [String: Any],
        _ context: HandlerContext,
        _ scope: GRDBReadScope
    ) throws -> String? {
        let kind = op["kind"] as? String ?? ""
        let hasId = !((op["id"] as? String) ?? "").isEmpty
        let hasTarget = !((op["target"] as? String) ?? "").isEmpty
        
        if hasId && hasTarget {
            return "pass `id` (note-scope) or `target` (corpus-scope), not both — a finding has one target"
        }
        
        if let code = dismissalPolicy.lintCode(of: kind) {
            if !lint.dismissibleCodes.contains(code) {
                let known = lint.dismissibleCodes.sorted().joined(separator: ", ")
                
                return lint.errorCodes.contains(code)
                    ? "lint code '\(code)' is an error, not a warn — invariant violations are not dismissible; fix it"
                    : "unknown dismissible lint code: \(code) (warns: \(known))"
            }
            
            let target: LintTarget = hasTarget
                ? .corpus(op["target"] as! String)
                : .note((op["id"] as? String) ?? "")
            let allFindings = try lint.scan(scope, id: nil, code: code, severity: nil, limit: nil, includeDismissed: true)
            let liveFindings = allFindings.filter { issue in issue.target == target }
            
            if liveFindings.isEmpty {
                let subjects = Set(
                    allFindings.map { issue in "\(issue.target.scope):\(issue.target.subject)" }
                ).sorted()
                let shown = subjects.prefix(5).joined(separator: ", ")
                let more = subjects.count > 5 ? " +\(subjects.count - 5) more" : ""
                
                return "no live '\(code)' finding on \(target.scope) '\(target.subject)' — nothing to dismiss"
                    + (shown.isEmpty ? "" : " (live subjects: \(shown)\(more))")
            }
            
            let selector = (op["finding"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            if let selector, !selector.isEmpty {
                let hits = liveFindings.filter { issue in issue.message.contains(selector) }
                
                if hits.isEmpty {
                    return "no '\(code)' finding on \(target.subject) contains \"\(selector.prefix(60))\" — "
                        + "dismiss the finding you actually reviewed"
                }
                
                if hits.count > 1 {
                    return "that `finding` selector is ambiguous — \(hits.count) '\(code)' findings on "
                        + "\(target.subject) match; give a longer substring"
                }
            } else if liveFindings.count > 1 {
                return "\(target.subject) has \(liveFindings.count) '\(code)' findings — pass `finding` to say which "
                    + "one you reviewed; dismissing the code outright would bury the others "
                    + "(and any added later)"
            }
            
            if hasTarget { return nil }
        } else if !Dismissals.dismissibleKinds.contains(kind) {
            return "invalid candidate kind: \(kind) (dismissible: "
                + "\(Dismissals.dismissibleKinds.sorted().joined(separator: " | ")) | lint:<warn-code>)"
        } else if hasTarget {
            return "`target` is for corpus-scope lint warns only — '\(kind)' is a note candidate, use `id`"
        }
        
        return try noteExistence.rejectionForUnknown(op["id"] as? String ?? "", context: context, scope: scope)
    }
    
    func write(
        _ op: [String: Any],
        _ context: HandlerContext,
        _ scope: GRDBScope
    ) throws -> [String: Any] {
        let now = context.now
        let target: LintTarget = ((op["target"] as? String)
            .map { value in value.isEmpty ? nil : value } ?? nil)
            .map { subject in LintTarget.corpus(subject) } ?? .note(op["id"] as! String)
        var kind = op["kind"] as! String
        
        if let code = dismissalPolicy.lintCode(of: kind),
            dismissalPolicy.lintFingerprint(of: kind) == nil {
            let liveFindings = try lint.scan(
                scope.readOnly,
                id: nil,
                code: code,
                severity: nil,
                limit: nil,
                includeDismissed: true
            )
                .filter { issue in issue.target == target }
            let selector = (op["finding"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let matched = (selector?.isEmpty == false)
                ? liveFindings.first { issue in issue.message.contains(selector!) }
                : (liveFindings.count == 1 ? liveFindings.first : nil)
            
            guard let matched else {
                throw OperationError.findingVanished(code: code, subject: target.subject)
            }
            
            kind = dismissalPolicy.lintKind(code, fingerprint: matched.dismissalKey)
        }
        
        try scope.run(RecordDismissalTransaction(target: target,
            kind: kind,
            reason: op["reason"] as? String,
            now: now))
        
        let ids: [String] = {
            if case .note(let noteId) = target { return [noteId] }
            
            return []
        }()
        
        return [
            "status": "ok",
            "ids": ids,
            "note": "dismissed \(kind) candidate on \(target.scope) '\(target.subject)'"
        ]
    }
    
    // MARK: - Private
}
