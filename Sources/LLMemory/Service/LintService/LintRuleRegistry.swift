//
//  LintRuleRegistry.swift
//  LLMemory
//
//  Created by JSilver on 8/7/26.
//

import Foundation

// The rule catalog — every rule this build knows, grouped by what it needs to
// see: a parsed document, a note, a note plus the DB, or the corpus plus the
// DB. Nothing here is a type member, so a caller holding the registry holds
// the whole vocabulary and cannot reach a rule the registry did not hand out.
struct LintRuleRegistry: Sendable {
    // MARK: - Property
    let documentRules: [any LintDocumentRule]

    let noteRules: [any NoteLintRule]

    let noteDBRules: [any NoteDBLintRule]

    let corpusDBRules: [any CorpusDBLintRule]

    var allRules: [(code: String, severity: LintSeverity)] {
        documentRules.map { rule in (rule.code, rule.severity) }
            + noteRules.map { rule in (rule.code, rule.severity) }
            + noteDBRules.map { rule in (rule.code, rule.severity) }
            + corpusDBRules.map { rule in (rule.code, rule.severity) }
    }

    var dismissibleCodes: Set<String> {
        Set(allRules.filter { rule in rule.severity == .warn }.map { rule in rule.code })
    }

    var errorCodes: Set<String> {
        Set(allRules.filter { rule in rule.severity == .error }.map { rule in rule.code })
    }

    // MARK: - Initializer
    // Every catalog defaults to what this build ships. They are parameters so a
    // caller can hand the scanner a different catalog — the alternative was a
    // side door on `lintAll`, which let a rule the registry never handed out
    // produce findings whose codes the registry does not know, and therefore
    // findings nobody can answer.
    init(
        documentRules: [any LintDocumentRule] = [
            FenceUnclosedRule(),
            BareHashLineRule(),
            WikilinkStyleRule(),
            HeadingSkipRule(),
            AdjacentEmptyHeadingRule(),
            EmptySectionRule()
        ],
        noteRules: [any NoteLintRule] = [
            InvalidIDRule(),
            InvalidPriorityRule(),
            AddressInFrontmatterRule(),
            NoTagsRule(),
            EmptySummaryRule(),
            SummaryLongRule(),
            EmptyTitleRule(),
            FieldTypoRule(),
            StaleSourceRule(),
            EmptyBodyRule(),
            TinyBodyRule(),
            PathCollisionRule(),
            DanglingNoteRefRule(),
            TagAliasViolationRule(),
            NoteOversizedRule(),
            GrowthUnboundedRule()
        ],
        noteDBRules: [any NoteDBLintRule] = [
            EnrichThinRule(),
            TemplateDriftRule()
        ],
        corpusDBRules: [any CorpusDBLintRule] = [
            IsolatedNoteRule(),
            FragmentUnlinkedRule(),
            GistMissingRule(),
            SingleTagRule(),
            TagNearDuplicateRule()
        ]
    ) {
        self.documentRules = documentRules
        self.noteRules = noteRules
        self.noteDBRules = noteDBRules
        self.corpusDBRules = corpusDBRules
    }

    // MARK: - Public
    func document(nid: String, body: String) -> LintDocument {
        let lines = body.unicodeLines()
        let fences = SectionEdit.scanFences(lines)
        var ancestors: [(level: Int, marker: String)] = []
        let sections = SectionEdit.splitSections(body).map { section -> LintSection in
            while let last = ancestors.last, last.level >= section.level {
                ancestors.removeLast()
            }
            
            let marker = "\(String(repeating: "#", count: section.level)) \(section.title)"
            let path = (ancestors.map(\.marker) + [marker]).joined(separator: " > ")
            ancestors.append((section.level, marker))
            
            return .init(
                level: section.level,
                title: section.title,
                lineStart: section.lineStart,
                lineEnd: section.lineEnd,
                path: path
            )
        }
        
        return LintDocument(
            id: nid,
            lines: lines,
            sections: sections,
            inFence: fences.mask,
            unclosedFence: fences.unclosedOpen
        )
    }

    // MARK: - Private
}
