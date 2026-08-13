//
//  Lint.swift
//  LLMemory
//
//  Created by JSilver on 8/7/26.
//

import Foundation

public enum Lint {
    public struct Issue: Encodable, Sendable {
        public enum CodingKeys: String, CodingKey {
            case severity, code, message, subject
            case targetScope = "target_scope"
        }
        
        // MARK: - Property
        public let severity: String
        public let code: String
        public let message: String
        public let target: LintTarget
        let key: String?
        
        var dismissalKey: String { key ?? code }
        
        // MARK: - Initializer
        public init(
            _ severity: String,
            _ code: String,
            _ message: String,
            _ target: LintTarget,
            key: String? = nil
        ) {
            self.severity = severity
            self.code = code
            self.message = message
            self.target = target
            self.key = key
        }
        
        // MARK: - Public
        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            
            try container.encode(severity, forKey: .severity)
            try container.encode(code, forKey: .code)
            try container.encode(message, forKey: .message)
            try container.encode(target.scope, forKey: .targetScope)
            try container.encode(target.subject, forKey: .subject)
        }
        
        // MARK: - Private
    }
    
    public struct RuleInfo: Encodable {
        // MARK: - Property
        public let code: String
        public let severity: String
        public let scope: String
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Public
    public static func ruleCatalog() -> [RuleInfo] {
        var rules: [RuleInfo] = []
        
        rules += LintRules.documentRules.map { rule in
            .init(code: rule.code, severity: rule.severity.rawValue, scope: "document")
        }
        rules += LintRules.noteRules.map { rule in
            .init(code: rule.code, severity: rule.severity.rawValue, scope: "note")
        }
        rules += LintRules.noteDBRules.map { rule in
            .init(code: rule.code, severity: rule.severity.rawValue, scope: "note+db")
        }
        rules += LintRules.corpusDBRules.map { rule in
            .init(code: rule.code, severity: rule.severity.rawValue, scope: "corpus+db")
        }
        
        return rules.sorted { lhs, rhs in (lhs.severity, lhs.code) < (rhs.severity, rhs.code) }
    }
    
    // The inspector core — runs the rule catalog, suppresses habituated
    // findings, and sorts for stable output. Stateless judgment over a
    // scope, callable by any service or handler without wiring.
    static func scan(
        _ scope: GRDBReadScope,
        id: String? = nil,
        code: String? = nil,
        severity: String? = nil,
        limit: Int? = nil,
        includeDismissed: Bool = false
    ) throws -> [Issue] {
        var issues = try id != nil
            ? lintNote(scope, nid: id!)
            : lintAll(scope)

        if !includeDismissed {
            issues = try suppressDismissed(scope, issues)
        }

        if let code { issues = issues.filter { issue in issue.code == code } }

        if let severity { issues = issues.filter { issue in issue.severity == severity } }

        issues.sort { lhs, rhs in
            if lhs.severity != rhs.severity { return lhs.severity == "error" }

            if lhs.target != rhs.target {
                if lhs.target.scope != rhs.target.scope {
                    return lhs.target.scope < rhs.target.scope
                }

                return lhs.target.subject < rhs.target.subject
            }

            if lhs.code != rhs.code { return lhs.code < rhs.code }

            return lhs.message < rhs.message
        }

        if let limit, issues.count > limit { issues = Array(issues.prefix(limit)) }

        return issues
    }

    static func lintNote(_ scope: GRDBReadScope, nid: String) throws -> [Issue] {
        checked(try lintNote(scope, nid: nid, index: scope.run(FetchLintCorpusIndexTransaction())))
    }
    
    static func lintAll(
        _ scope: GRDBReadScope,
        corpusRules: [any CorpusDBLintRule] = LintRules.corpusDBRules
    ) throws -> [Issue] {
        let index = try scope.run(FetchLintCorpusIndexTransaction())
        var issues: [Issue] = []
        
        for nid in index.ids.sorted() {
            issues.append(contentsOf: try lintNote(scope, nid: nid, index: index))
        }
        
        for rule in corpusRules {
            issues.append(contentsOf: try rule.check(scope).map { finding in
                corpusIssue(code: rule.code, severity: rule.severity.rawValue, finding)
            })
        }
        
        return checked(issues)
    }
    
    static func corpusIssue(
        code: String,
        severity: String,
        _ finding: LintEngine.Finding
    ) -> Issue {
        guard let target = finding.target else {
            return Issue(
                "error",
                "lint-rule-untargeted",
                "corpus rule '\(code)' emitted a finding with no target — a dismissal "
                + "identity cannot be formed, so the finding is unanswerable; the rule "
                + "must declare `.corpus(<stable key>)`. finding: \(finding.message)",
                .corpus("rule:\(code)"),
                key: finding.message
            )
        }
        
        return Issue(severity, code, finding.message, target, key: finding.key)
    }
    
    static func suppressDismissed(_ scope: GRDBReadScope, _ issues: [Issue]) throws -> [Issue] {
        let dismissals = try scope.run(FetchLintDismissalsTransaction())
        
        if dismissals.isEmpty { return issues }
        
        let generation = try scope.run(FetchCandidateGenerationTransaction())
        var shapes: [String: (words: Int, sections: Int)] = [:]
        
        return try issues.filter { issue in
            guard issue.severity == "warn" else { return true }
            
            let fine = Dismissals.lintKind(issue.code, fingerprint: issue.dismissalKey)
            let coarse = Dismissals.lintKind(issue.code)
            
            guard let dismissal = dismissals[Dismissals.lintLookupKey(issue.target, fine)]
                ?? dismissals[Dismissals.lintLookupKey(issue.target, coarse)]
            else {
                return true
            }
            
            switch issue.target {
            case .corpus:
                return Dismissals.corpusGate(dismissal, globalGeneration: generation).surface
            
            case .note(let nid):
                if shapes[nid] == nil {
                    shapes[nid] = try scope.run(FetchNoteShapeTransaction(nid: nid))
                }
                
                let shape = shapes[nid]!
                
                return Dismissals.gate(
                    dismissal,
                    currentWords: shape.words,
                    currentSections: shape.sections,
                    globalGeneration: generation
                ).surface
            }
        }
    }
    
    static func checked(_ issues: [Issue]) -> [Issue] {
        var seen = Set<String>()
        var checkedIssues: [Issue] = []
        
        for issue in issues {
            let identity = "\(issue.target.storageKey)\u{0}\(issue.code)\u{0}\(issue.key ?? "")"
            
            if seen.insert(identity).inserted {
                checkedIssues.append(issue)
                continue
            }
            
            let keyDescription = issue.key.map { key in "key '\(key)'" }
                ?? "no key — a rule with several findings per target must declare one"
            
            checkedIssues.append(
                Issue(
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
    private static func lintNote(
        _ scope: GRDBReadScope,
        nid: String,
        index: LintCorpusIndex
    ) throws -> [Issue] {
        guard try scope.run(FetchNoteLintHeaderTransaction(nid: nid)) else {
            return [Issue("error", "missing", "note not in db: \(nid)", .note(nid))]
        }
        
        let relativePath = Paths.relativeFile(forId: nid)
        let path = Paths.file(forId: nid)
        
        if !FileManager.default.fileExists(atPath: path.path) {
            return [Issue("error", "file-missing", "file does not exist: \(relativePath)", .note(nid))]
        }
        
        let document: FrontmatterDoc
        let body: String
        do {
            let text = try String(contentsOf: path, encoding: .utf8)
            (document, body) = try Frontmatter.parse(text)
        } catch {
            return [Issue("error", "frontmatter-parse", "parse failed: \(error)", .note(nid))]
        }
        
        let note = NoteLintInput(
            nid: nid,
            doc: document,
            body: body,
            document: LintRules.document(nid: nid, body: body)
        )
        var issues: [Issue] = []
        
        issues.append(
            contentsOf: LintEngine.run(LintRules.documentRules, over: note.document).map { output in
                Issue(
                    output.severity.rawValue,
                    output.code,
                    output.message,
                    output.target,
                    key: output.key
                )
            }
        )
        
        for rule in LintRules.noteRules {
            issues.append(contentsOf: rule.check(note, index).map { finding in
                Issue(
                    rule.severity.rawValue,
                    rule.code,
                    finding.message,
                    finding.target ?? .note(nid),
                    key: finding.key
                )
            })
        }
        
        for rule in LintRules.noteDBRules {
            issues.append(contentsOf: try rule.check(scope, note: note).map { finding in
                Issue(
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
