//
//  LintScanner.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

// The inspector core — runs the rule catalog over a scope, suppresses the
// findings a person has reviewed and kept, and sorts what is left so the same
// corpus always reports in the same order.
struct LintScanner: LintScanning {
    // MARK: - Property
    let rules: LintRuleRegistry

    // The brain being inspected — its config sets the thresholds the rules
    // judge by, and its layout says where a note id lives. Taken here rather
    // than off the handle it is given: a database answers neither.
    let brain: BrainContext
    
    private let engine = LintEngine()
    
    var dismissibleCodes: Set<String> { rules.dismissibleCodes }
    
    var errorCodes: Set<String> { rules.errorCodes }
    
    private let frontmatter = Frontmatter()
    
    private let dismissalPolicy = DismissalPolicy()

    // The thresholds this brain judges by. Read from the cache each time
    // rather than held: a scanner outlives the scope it was built in, and a
    // held value would score a later pass against a bar the brain has left.
    private var tuning: LintTuning { LintTuning(brain.config) }

    // One spelling of the corpus read, so a single-note lint and a full pass
    // score against the same thresholds.
    private var corpusIndexTransaction: FetchLintCorpusIndexTransaction {
        FetchLintCorpusIndexTransaction(
            oversizedWords: tuning.oversizedWords,
            growthMinDatedSections: tuning.growthMinDatedSections
        )
    }
    
    // MARK: - Initializer
    init(rules: LintRuleRegistry, brain: BrainContext) {
        self.rules = rules
        self.brain = brain
    }
    
    // MARK: - Public
    func ruleCatalog() -> [LintRuleInfo] {
        var catalog: [LintRuleInfo] = []
        
        catalog += rules.documentRules.map { rule in
            .init(code: rule.code, severity: rule.severity.rawValue, db: "document")
        }
        catalog += rules.noteRules.map { rule in
            .init(code: rule.code, severity: rule.severity.rawValue, db: "note")
        }
        catalog += rules.noteDBRules.map { rule in
            .init(code: rule.code, severity: rule.severity.rawValue, db: "note+db")
        }
        catalog += rules.corpusDBRules.map { rule in
            .init(code: rule.code, severity: rule.severity.rawValue, db: "corpus+db")
        }
        
        return catalog.sorted { lhs, rhs in (lhs.severity, lhs.code) < (rhs.severity, rhs.code) }
    }
    
    // The inspector core — runs the rule catalog, suppresses habituated
    // findings, and sorts for stable output.
    func scan(
        _ db: Database,
        id: String?,
        code: String?,
        severity: String?,
        limit: Int?,
        includeDismissed: Bool
    ) throws -> [LintIssue] {
        var issues = try id != nil
            ? lintNote(db, nid: id!)
            : lintAll(db)
        
        if !includeDismissed {
            issues = try suppressDismissed(db, issues)
        }
        
        if let code { issues = issues.filter { issue in issue.code == code } }
        
        if let severity { issues = issues.filter { issue in issue.severity == severity } }
        
        issues.sort { lhs, rhs in
            if lhs.severity != rhs.severity { return lhs.severity == "error" }
            
            if lhs.target != rhs.target {
                if lhs.target.db != rhs.target.db {
                    return lhs.target.db < rhs.target.db
                }
                
                return lhs.target.subject < rhs.target.subject
            }
            
            if lhs.code != rhs.code { return lhs.code < rhs.code }
            
            return lhs.message < rhs.message
        }
        
        if let limit, issues.count > limit { issues = Array(issues.prefix(limit)) }
        
        return issues
    }
    
    func lintNote(_ db: Database, nid: String) throws -> [LintIssue] {
        checked(try lintNote(db, nid: nid, index: db.run(corpusIndexTransaction)))
    }
    
    func lintAll(_ db: Database) throws -> [LintIssue] {
        let index = try db.run(corpusIndexTransaction)
        var issues: [LintIssue] = []
        
        for nid in index.ids.sorted() {
            issues.append(contentsOf: try lintNote(db, nid: nid, index: index))
        }
        
        for rule in rules.corpusDBRules {
            issues.append(contentsOf: try rule.check(db, tuning).map { finding in
                corpusIssue(code: rule.code, severity: rule.severity.rawValue, finding)
            })
        }
        
        return checked(issues)
    }
    
    func corpusIssue(
        code: String,
        severity: String,
        _ finding: LintFinding
    ) -> LintIssue {
        guard let target = finding.target else {
            return LintIssue(
                "error",
                "lint-rule-untargeted",
                "corpus rule '\(code)' emitted a finding with no target — a dismissal "
                + "identity cannot be formed, so the finding is unanswerable; the rule "
                + "must declare `.corpus(<stable key>)`. finding: \(finding.message)",
                .corpus("rule:\(code)"),
                key: finding.message
            )
        }
        
        return LintIssue(severity, code, finding.message, target, key: finding.key)
    }
    
    func suppressDismissed(_ db: Database, _ issues: [LintIssue]) throws -> [LintIssue] {
        let dismissals = try db.run(FetchLintDismissalsTransaction())
        
        if dismissals.isEmpty { return issues }
        
        let generation = try db.run(FetchCandidateGenerationTransaction())
        var shapes: [String: (words: Int, sections: Int)] = [:]
        
        return try issues.filter { issue in
            guard issue.severity == "warn" else { return true }
            
            let fine = dismissalPolicy.lintKind(issue.code, fingerprint: issue.dismissalKey)
            let coarse = dismissalPolicy.lintKind(issue.code)
            
            guard let dismissal = dismissals[dismissalPolicy.lintLookupKey(issue.target, fine)]
                ?? dismissals[dismissalPolicy.lintLookupKey(issue.target, coarse)]
            else {
                return true
            }
            
            switch issue.target {
            case .corpus:
                return dismissalPolicy.corpusGate(dismissal, globalGeneration: generation).surface
            
            case .note(let nid):
                if shapes[nid] == nil {
                    shapes[nid] = try db.run(FetchNoteShapeTransaction(nid: nid))
                }
                
                let shape = shapes[nid]!
                
                return dismissalPolicy.gate(
                    dismissal,
                    config: brain.config,
                    currentWords: shape.words,
                    currentSections: shape.sections,
                    globalGeneration: generation
                ).surface
            }
        }
    }
    
    func checked(_ issues: [LintIssue]) -> [LintIssue] {
        var seen = Set<String>()
        var checkedIssues: [LintIssue] = []
        
        for issue in issues {
            let identity = "\(issue.target.storageKey)\u{0}\(issue.code)\u{0}\(issue.key ?? "")"
            
            if seen.insert(identity).inserted {
                checkedIssues.append(issue)
                continue
            }
            
            let keyDescription = issue.key.map { key in "key '\(key)'" }
                ?? "no key — a rule with several findings per target must declare one"
            
            checkedIssues.append(
                LintIssue(
                    "error",
                    "lint-rule-identity-collision",
                    "lint rule '\(issue.code)' reported two findings sharing one identity on "
                    + "'\(issue.target.subject)' (\(keyDescription)): a keep-decision on either "
                    + "would silently hide the other. dropped: \(issue.message)",
                    issue.target,
                    key: "collision:\(issue.code):\(issue.key ?? "")"
                )
            )
        }
        
        return checkedIssues
    }
    
    // MARK: - Private
    // The frontmatter block only — an "id:" further down is prose.
    private func declaredId(in text: String) -> String? {
        var seenOpen = false
        
        for line in text.unicodeLines() {
            if line == "---" {
                if seenOpen { return nil }
                
                seenOpen = true
                continue
            }
            
            guard seenOpen else { return nil }
            
            if line.hasPrefix("id:") {
                return String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            }
        }
        
        return nil
    }
    
    private func lintNote(
        _ db: Database,
        nid: String,
        index: LintCorpusIndex
    ) throws -> [LintIssue] {
        guard try db.run(NoteExistsTransaction(nid: nid)) else {
            return [LintIssue("error", "missing", "note not in db: \(nid)", .note(nid))]
        }
        
        let relativePath = brain.layout.relativeFile(forId: nid)
        let path = brain.layout.file(forId: nid)
        
        if !FileManager.default.fileExists(atPath: path.path) {
            return [LintIssue("error", "file-missing", "file does not exist: \(relativePath)", .note(nid))]
        }
        
        let document: FrontmatterDocument
        let body: String
        let text: String
        do {
            text = try String(contentsOf: path, encoding: .utf8)
            (document, body) = try frontmatter.parse(text)
        } catch {
            return [LintIssue("error", "frontmatter-parse", "parse failed: \(error)", .note(nid))]
        }
        
        let note = NoteLintInput(
            nid: nid,
            declaredId: declaredId(in: text),
            doc: document,
            body: body,
            document: rules.document(nid: nid, body: body)
        )
        var issues: [LintIssue] = []
        
        issues.append(
            contentsOf: engine.run(rules.documentRules, over: note.document).map { output in
                LintIssue(
                    output.severity.rawValue,
                    output.code,
                    output.message,
                    output.target,
                    key: output.key
                )
            }
        )
        
        for rule in rules.noteRules {
            issues.append(contentsOf: rule.check(note, index).map { finding in
                LintIssue(
                    rule.severity.rawValue,
                    rule.code,
                    finding.message,
                    finding.target ?? .note(nid),
                    key: finding.key
                )
            })
        }
        
        for rule in rules.noteDBRules {
            issues.append(contentsOf: try rule.check(db, brain, note: note).map { finding in
                LintIssue(
                    rule.severity.rawValue,
                    rule.code,
                    finding.message,
                    finding.target ?? .note(nid),
                    key: finding.key
                )
            })
        }
        
        return issues
    }
}
