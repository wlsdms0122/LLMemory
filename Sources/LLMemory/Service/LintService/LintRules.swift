//
//  LintRules.swift
//  LLMemory
//
//  Created by JSilver on 8/7/26.
//

import Foundation

private let hangulRegex = try! NSRegularExpression(pattern: #"[가-힣]"#)

protocol NoteLintRule: LintRuleMeta {
    func check(_ note: NoteLintInput, _ index: LintCorpusIndex) -> [LintEngine.Finding]
}

protocol NoteDBLintRule: LintRuleMeta {
    func check(_ scope: GRDBReadScope, note: NoteLintInput) throws -> [LintEngine.Finding]
}

protocol CorpusDBLintRule: LintRuleMeta {
    func check(_ scope: GRDBReadScope) throws -> [LintEngine.Finding]
}

struct NoteLintInput {
    // MARK: - Property
    let nid: String
    let doc: FrontmatterDoc
    let body: String
    let document: LintEngine.Document
    
    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}

struct LintCorpusIndex {
    // MARK: - Property
    let ids: Set<String>
    let tagAliases: [String: String]
    
    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}

enum LintRules {
    // MARK: - Property
    static let documentRules: [any LintDocumentRule] = [
        FenceUnclosedRule(),
        BareHashLineRule(),
        WikilinkStyleRule(),
        HeadingSkipRule(),
        AdjacentEmptyHeadingRule(),
        EmptySectionRule()
    ]
    
    static let noteRules: [any NoteLintRule] = [
        InvalidIDRule(),
        InvalidPriorityRule(),
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
    ]
    
    static let noteDBRules: [any NoteDBLintRule] = [
        EnrichThinRule(),
        TemplateDriftRule()
    ]
    
    static let corpusDBRules: [any CorpusDBLintRule] = [
        IsolatedNoteRule(),
        FragmentUnlinkedRule(),
        GistMissingRule(),
        SingleTagRule(),
        TagNearDuplicateRule()
    ]
    
    static var allRules: [(code: String, severity: LintEngine.Severity)] {
        documentRules.map { rule in (rule.code, rule.severity) }
            + noteRules.map { rule in (rule.code, rule.severity) }
            + noteDBRules.map { rule in (rule.code, rule.severity) }
            + corpusDBRules.map { rule in (rule.code, rule.severity) }
    }
    
    static var dismissibleCodes: Set<String> {
        Set(allRules.filter { rule in rule.severity == .warn }.map { rule in rule.code })
    }
    
    static var errorCodes: Set<String> {
        Set(allRules.filter { rule in rule.severity == .error }.map { rule in rule.code })
    }
    
    // MARK: - Initializer
    // MARK: - Public
    static func document(nid: String, body: String) -> LintEngine.Document {
        let lines = body.unicodeLines()
        let fences = SectionEdit.scanFences(lines)
        var ancestors: [(level: Int, marker: String)] = []
        let sections = SectionEdit.splitSections(body).map { section -> LintEngine.Section in
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
        
        return LintEngine.Document(
            id: nid,
            lines: lines,
            sections: sections,
            inFence: fences.mask,
            unclosedFence: fences.unclosedOpen
        )
    }
    
    // MARK: - Private
}

enum FamilyView {
    struct Family {
        // MARK: - Property
        let stem: String?
        let members: [String]
        let hasIndex: Bool
        let key: String
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Public
    static func families(_ scope: GRDBReadScope) throws -> [Family] {
        let minFamily = Config.getInt("lint.fragment_min_family", default: 3)
        let graph = try scope.run(FetchFamilyGraphTransaction())
        let allIds = Set(graph.notes)
        var adjacency: [String: [String]] = [:]
        
        for link in graph.siblingLinks {
            guard allIds.contains(link.src), allIds.contains(link.dst) else { continue }
            
            adjacency[link.src, default: []].append(link.dst)
            adjacency[link.dst, default: []].append(link.src)
        }
        
        var components: [[String]] = []
        var componentOf: [String: Int] = [:]
        var visited: Set<String> = []
        
        for start in adjacency.keys.sorted() {
            guard !visited.contains(start) else { continue }
            
            var component: [String] = []
            var stack = [start]
            
            while let node = stack.popLast() {
                guard !visited.contains(node) else { continue }
                
                visited.insert(node)
                component.append(node)
                stack.append(contentsOf: adjacency[node] ?? [])
            }
            
            component.sort()
            
            for id in component { componentOf[id] = components.count }
            
            components.append(component)
        }
        
        var grouped: [String: [String]] = [:]
        
        // The naming-convention oracle, now scoped by the parent address:
        // two notes only look like siblings if they sit in the same branch.
        for id in graph.notes {
            let labels = id.split(separator: ".").map(String.init)
            
            guard let leaf = labels.last, let cut = leaf.lastIndex(of: "-") else { continue }
            
            let stem = String(leaf[leaf.startIndex..<cut])
            
            guard stem.count >= 4, stem.contains("-") else { continue }
            
            grouped["\(labels.dropLast().joined(separator: "."))\u{0}\(stem)", default: []].append(id)
        }
        
        var absorbed: [Int: Set<String>] = [:]
        var pure: [[String]] = []
        
        for (_, members) in grouped.sorted(by: { lhs, rhs in lhs.key < rhs.key }) {
            var hits: [Int: Int] = [:]
            
            for member in members {
                if let component = componentOf[member] { hits[component, default: 0] += 1 }
            }
            
            if let target = hits.max(by: { lhs, rhs in
                (lhs.value, -lhs.key) < (rhs.value, -rhs.key)
            })?.key {
                for member in members where componentOf[member] == nil {
                    absorbed[target, default: []].insert(member)
                }
            } else if members.count >= minFamily {
                pure.append(members.sorted())
            }
        }
        
        var families: [Family] = []
        
        for (index, component) in components.enumerated() {
            let members = (component + Array(absorbed[index] ?? [])).sorted()
            families.append(makeFamily(members, allIds: allIds))
        }
        
        families.append(contentsOf: pure.map { members in makeFamily(members, allIds: allIds) })
        
        return families.sorted { lhs, rhs in
            (lhs.stem ?? "", lhs.key) < (rhs.stem ?? "", rhs.key)
        }
    }
    
    static func unlinkedMembers(_ scope: GRDBReadScope, _ family: Family) throws -> [String] {
        let inFamily = Set(family.members).union(family.stem.map { stem in [stem] } ?? [])
        var unlinked: [String] = []
        
        for member in family.members {
            let neighbours = try scope.run(FetchDeliberateNeighborsTransaction(noteId: member))
            
            if neighbours.contains(where: { other in inFamily.contains(other) }) { continue }
            
            unlinked.append(member)
        }
        
        return unlinked
    }
    
    // MARK: - Private
    private static func makeFamily(_ members: [String], allIds: Set<String>) -> Family {
        let stem = commonStem(of: members)
        let hasIndex = stem.map { stem in allIds.contains(stem) } ?? false
        let first = members.first ?? ""
        
        return Family(
            stem: stem,
            members: members,
            hasIndex: hasIndex,
            key: hasIndex ? (stem ?? first) : first
        )
    }
    
    private static func commonStem(of ids: [String]) -> String? {
        guard var prefix = ids.first else { return nil }
        
        for id in ids.dropFirst() {
            while id != prefix && !id.hasPrefix(prefix + "-") {
                guard let cut = prefix.lastIndex(of: "-") else { return nil }
                
                prefix = String(prefix[prefix.startIndex..<cut])
            }
        }
        
        guard prefix.count >= 4, prefix.contains("-") else { return nil }
        
        return prefix
    }
}

struct FenceUnclosedRule: LintDocumentRule {
    // MARK: - Property
    let code = "fence-unclosed"
    let severity = LintEngine.Severity.error
    
    // MARK: - Initializer
    // MARK: - Public
    func check(_ doc: LintEngine.Document) -> [LintEngine.Finding] {
        guard let openLine = doc.unclosedFence else { return [] }
        
        return [
            .init("unclosed code fence (opened at line \(openLine + 1)) — the rest of the body is treated as fenced")
        ]
    }
    
    // MARK: - Private
}

struct BareHashLineRule: LintDocumentRule {
    // MARK: - Property
    let code: String
    let severity: LintEngine.Severity
    let pattern: LintLinePatternRule
    
    // MARK: - Initializer
    init() {
        code = "bare-hash-line"
        severity = .warn
        pattern = LintLinePatternRule(
            code: code,
            severity: severity,
            pattern: #"^#{1,6}[^#\s]"#
        ) { lineNumber, line in
            "no space after leading # (line \(lineNumber)): \(line.prefix(40)) — heading typo or unescaped channel name"
        }
    }
    
    // MARK: - Public
    func check(_ doc: LintEngine.Document) -> [LintEngine.Finding] { pattern.check(doc) }
    
    // MARK: - Private
}

struct WikilinkStyleRule: LintDocumentRule {
    // MARK: - Property
    let code = "wikilink-style"
    let severity = LintEngine.Severity.warn
    
    private static let wikilinkRegex = try! NSRegularExpression(
        pattern: #"\[\[([a-z0-9][a-z0-9-]*)\]\]"#
    )
    
    // MARK: - Initializer
    // MARK: - Public
    func check(_ doc: LintEngine.Document) -> [LintEngine.Finding] {
        var hits: [(id: String, line: Int)] = []
        
        for index in doc.contentLineIndices() {
            let line = doc.lines[index]
            let nsLine = line as NSString
            
            Self.wikilinkRegex.enumerateMatches(
                in: line,
                range: NSRange(location: 0, length: nsLine.length)
            ) { match, _, _ in
                guard let match else { return }
                
                let range = match.range
                let before = range.location > 0
                    ? nsLine.substring(with: NSRange(location: range.location - 1, length: 1))
                    : ""
                let afterLocation = range.location + range.length
                let after = afterLocation < nsLine.length
                    ? nsLine.substring(with: NSRange(location: afterLocation, length: 1))
                    : ""
                
                if before == "`" || after == "`" { return }
                
                hits.append((nsLine.substring(with: match.range(at: 1)), index + 1))
            }
        }
        
        return LintEngine.groupBySubject(hits, by: \.id).map { id, occurrences in
            let lines = occurrences.map(\.line)
            
            return .init(
                "wikilink `[[\(id)]]` (line \(lines[0])) — use a backtick reference `\(id)` instead"
                    + LintEngine.repeatSuffix(lines),
                key: "wikilink:\(id)"
            )
        }
    }
    
    // MARK: - Private
}

struct HeadingSkipRule: LintDocumentRule {
    // MARK: - Property
    let code = "heading-skip"
    let severity = LintEngine.Severity.warn
    
    // MARK: - Initializer
    // MARK: - Public
    func check(_ doc: LintEngine.Document) -> [LintEngine.Finding] {
        var hits: [(from: Int, to: Int, path: String, line: Int)] = []
        var previousLevel: Int? = nil
        
        for section in doc.sections.sorted(by: { lhs, rhs in lhs.lineStart < rhs.lineStart }) {
            if let previousLevel, section.level > previousLevel + 1 {
                hits.append((previousLevel, section.level, section.path, section.lineStart + 1))
            }
            
            previousLevel = section.level
        }
        
        return LintEngine
            .groupBySubject(hits, by: { hit in "\(hit.from)→\(hit.to)\u{0}\(hit.path)" })
            .map { _, occurrences in
                let hit = occurrences[0]
                let lines = occurrences.map(\.line)
                
                return .init(
                    "heading level jump h\(hit.from)→h\(hit.to) (line \(lines[0]): '\(hit.path.prefix(60))')"
                        + LintEngine.repeatSuffix(lines),
                    key: "skip:h\(hit.from)-h\(hit.to):\(hit.path)"
                )
            }
    }
    
    // MARK: - Private
}

struct AdjacentEmptyHeadingRule: LintDocumentRule {
    // MARK: - Property
    let code = "adjacent-empty-heading"
    let severity = LintEngine.Severity.warn
    
    // MARK: - Initializer
    // MARK: - Public
    func check(_ doc: LintEngine.Document) -> [LintEngine.Finding] {
        let hits = doc.sections.filter { section in section.lineEnd == section.lineStart + 1 }
        
        return LintEngine.groupBySubject(hits, by: \.path).map { _, sections in
            let section = sections[0]
            let lines = sections.map { section in section.lineStart + 1 }
            
            return .init(
                "heading immediately followed by another heading: \(section.path) (line \(lines[0])) — likely lost or displaced body"
                    + LintEngine.repeatSuffix(lines),
                key: "adjacent:\(section.path)"
            )
        }
    }
    
    // MARK: - Private
}

struct EmptySectionRule: LintDocumentRule {
    // MARK: - Property
    let code = "empty-section"
    let severity = LintEngine.Severity.warn
    
    // MARK: - Initializer
    // MARK: - Public
    func check(_ doc: LintEngine.Document) -> [LintEngine.Finding] {
        let hits = doc.sections.filter { section in
            let inner = doc.lines[(section.lineStart + 1)..<section.lineEnd]
            
            return !inner.contains(where: { line in
                !line.trimmingCharacters(in: .whitespaces).isEmpty
            })
        }
        
        return LintEngine.groupBySubject(hits, by: \.path).map { _, sections in
            let section = sections[0]
            let lines = sections.map { section in section.lineStart + 1 }
            
            return .init(
                "empty section: \(section.path) (line \(lines[0]))"
                    + LintEngine.repeatSuffix(lines),
                key: "empty:\(section.path)"
            )
        }
    }
    
    // MARK: - Private
}

struct InvalidIDRule: NoteLintRule {
    // MARK: - Property
    let code = "invalid-id"
    let severity = LintEngine.Severity.error
    
    // MARK: - Initializer
    // MARK: - Public
    func check(_ note: NoteLintInput, _ index: LintCorpusIndex) -> [LintEngine.Finding] {
        let nsId = note.nid as NSString
        
        guard Paths.idRegex.firstMatch(
            in: note.nid,
            range: NSRange(location: 0, length: nsId.length)
        ) == nil else {
            return []
        }
        
        return [.init("id must be dot-joined kebab-case labels: '\(note.nid)'")]
    }
    
    // MARK: - Private
}

struct InvalidPriorityRule: NoteLintRule {
    // MARK: - Property
    let code = "invalid-priority"
    let severity = LintEngine.Severity.error
    
    private static let valid: Set<String> = ["eager", "lazy"]
    
    // MARK: - Initializer
    // MARK: - Public
    func check(_ note: NoteLintInput, _ index: LintCorpusIndex) -> [LintEngine.Finding] {
        guard !Self.valid.contains(note.doc.priority) else { return [] }
        
        return [.init("priority must be eager|lazy: '\(note.doc.priority)'")]
    }
    
    // MARK: - Private
}

struct NoTagsRule: NoteLintRule {
    // MARK: - Property
    let code = "no-tags"
    let severity = LintEngine.Severity.warn
    
    // MARK: - Initializer
    // MARK: - Public
    func check(_ note: NoteLintInput, _ index: LintCorpusIndex) -> [LintEngine.Finding] {
        note.doc.tags.isEmpty ? [.init("tags is empty")] : []
    }
    
    // MARK: - Private
}

struct EmptySummaryRule: NoteLintRule {
    // MARK: - Property
    let code = "empty-summary"
    let severity = LintEngine.Severity.warn
    
    // MARK: - Initializer
    // MARK: - Public
    func check(_ note: NoteLintInput, _ index: LintCorpusIndex) -> [LintEngine.Finding] {
        note.doc.summary.isEmpty ? [.init("summary is empty")] : []
    }
    
    // MARK: - Private
}

struct SummaryLongRule: NoteLintRule {
    // MARK: - Property
    let code = "summary-long"
    let severity = LintEngine.Severity.warn
    
    // MARK: - Initializer
    // MARK: - Public
    func check(_ note: NoteLintInput, _ index: LintCorpusIndex) -> [LintEngine.Finding] {
        guard note.doc.summary.count > 80 else { return [] }
        
        return [.init("summary \(note.doc.summary.count) chars (recommended ≤80)")]
    }
    
    // MARK: - Private
}

struct EmptyTitleRule: NoteLintRule {
    // MARK: - Property
    let code = "empty-title"
    let severity = LintEngine.Severity.warn
    
    // MARK: - Initializer
    // MARK: - Public
    func check(_ note: NoteLintInput, _ index: LintCorpusIndex) -> [LintEngine.Finding] {
        note.doc.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? [.init("title is empty")]
            : []
    }
    
    // MARK: - Private
}

// A field llmemory does not know is not a defect — that is what custom fields
// are. What is still a defect is a *near miss*: `summry:` parses fine, lands in
// extra, and leaves the real summary empty. Only edit-distance-1 neighbours of a
// first-class field are worth a word.
struct FieldTypoRule: NoteLintRule {
    // MARK: - Property
    let code = "field-typo"
    let severity = LintEngine.Severity.warn
    
    // MARK: - Initializer
    // MARK: - Public
    func check(_ note: NoteLintInput, _ index: LintCorpusIndex) -> [LintEngine.Finding] {
        note.doc.extra.keys.sorted().compactMap { field in
            guard let known = Frontmatter.knownFields.first(
                where: { known in withinEdit1(field, known) }
            ) else {
                return nil
            }
            
            return .init(
                "custom field '\(field)' is one edit from '\(known)' — typo, or meant as its own field?",
                key: "field:\(field)"
            )
        }
    }
    
    // MARK: - Private
}

struct StaleSourceRule: NoteLintRule {
    // MARK: - Property
    let code = "stale-source"
    let severity = LintEngine.Severity.warn
    
    // MARK: - Initializer
    // MARK: - Public
    func check(_ note: NoteLintInput, _ index: LintCorpusIndex) -> [LintEngine.Finding] {
        note.doc.source
            .filter { source in
                SourceFingerprint.isDriftCheckable(source)
                    && !FileManager.default.fileExists(
                        atPath: (source as NSString).expandingTildeInPath
                    )
            }
            .map { source in
                .init("source path does not exist: \(source)", key: "source:\(source)")
            }
    }
    
    // MARK: - Private
}

struct EmptyBodyRule: NoteLintRule {
    // MARK: - Property
    let code = "empty-body"
    let severity = LintEngine.Severity.warn
    
    // MARK: - Initializer
    // MARK: - Public
    func check(_ note: NoteLintInput, _ index: LintCorpusIndex) -> [LintEngine.Finding] {
        note.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? [.init("body is empty")]
            : []
    }
    
    // MARK: - Private
}

struct TinyBodyRule: NoteLintRule {
    // MARK: - Property
    let code = "tiny-body"
    let severity = LintEngine.Severity.warn
    
    // MARK: - Initializer
    // MARK: - Public
    func check(_ note: NoteLintInput, _ index: LintCorpusIndex) -> [LintEngine.Finding] {
        let trimmed = note.body.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmed.isEmpty, SectionEdit.wordCount(note.body) < 5 else { return [] }
        
        return [.init("body has fewer than 5 words")]
    }
    
    // MARK: - Private
}

struct PathCollisionRule: NoteLintRule {
    // MARK: - Property
    let code = "path-collision"
    let severity = LintEngine.Severity.error
    
    // MARK: - Initializer
    // MARK: - Public
    func check(_ note: NoteLintInput, _ index: LintCorpusIndex) -> [LintEngine.Finding] {
        SectionEdit.findPathCollisions(note.body).map { collision in
            .init(
                "section path collision: \(collision.display())",
                key: "path:\(collision.path.display())"
            )
        }
    }
    
    // MARK: - Private
}

struct DanglingNoteRefRule: NoteLintRule {
    // MARK: - Property
    let code = "dangling-note-ref"
    let severity = LintEngine.Severity.warn
    
    private static let tokenRegex = try! NSRegularExpression(
        pattern: #"`([a-z][a-z0-9-]{3,})`"#
    )
    private static let wikilinkRegex = try! NSRegularExpression(
        pattern: #"\[\[([a-z][a-z0-9-]{3,})\]\]"#
    )
    
    // MARK: - Initializer
    // MARK: - Public
    func check(_ note: NoteLintInput, _ index: LintCorpusIndex) -> [LintEngine.Finding] {
        var seen = Set<String>()
        var findings: [LintEngine.Finding] = []
        
        for lineIndex in note.document.contentLineIndices() {
            let line = note.document.lines[lineIndex]
            let nsLine = line as NSString
            let range = NSRange(location: 0, length: nsLine.length)
            
            for regex in [Self.tokenRegex, Self.wikilinkRegex] {
                regex.enumerateMatches(in: line, range: range) { match, _, _ in
                    guard let match else { return }
                    
                    let token = nsLine.substring(with: match.range(at: 1))
                    
                    guard token.contains("-"),
                        token != note.nid,
                        !index.ids.contains(token),
                        seen.insert(token).inserted
                    else {
                        return
                    }
                    
                    guard let nearest = Self.nearestId(
                        token,
                        index.ids,
                        excluding: note.nid
                    ) else {
                        return
                    }
                    
                    findings.append(
                        .init(
                            "body reference `\(token)` is not a note id (body line \(lineIndex + 1)) — nearest id: \(nearest)",
                            key: "tok:\(token)"
                        )
                    )
                }
            }
        }
        
        return findings
    }
    
    static func nearestId(
        _ token: String,
        _ ids: Set<String>,
        excluding nid: String
    ) -> String? {
        var edit1: [String] = []
        var extensions: [String] = []
        
        for id in ids where id != nid {
            if withinEdit1(id, token) {
                edit1.append(id)
            } else if id.hasPrefix(token + "-") || id.hasSuffix("-" + token) {
                extensions.append(id)
            }
        }
        
        if extensions.count > 1 && edit1.isEmpty { return nil }
        
        if let typo = edit1.min() { return typo }
        
        return extensions.min()
    }
    
    // MARK: - Private
}

struct TagAliasViolationRule: NoteLintRule {
    // MARK: - Property
    let code = "tag-alias-violation"
    let severity = LintEngine.Severity.warn
    
    // MARK: - Initializer
    // MARK: - Public
    func check(_ note: NoteLintInput, _ index: LintCorpusIndex) -> [LintEngine.Finding] {
        note.doc.tags.compactMap { tag in
            guard let canonical = index.tagAliases[tag] else { return nil }
            
            return .init(
                "frontmatter tag '\(tag)' is an old form canonicalized to '\(canonical)' — drift from an edit outside ops",
                key: "tag:\(tag)"
            )
        }
    }
    
    // MARK: - Private
}

struct NoteOversizedRule: NoteLintRule {
    // MARK: - Property
    let code = "note-oversized"
    let severity = LintEngine.Severity.warn
    
    // MARK: - Initializer
    // MARK: - Public
    func check(_ note: NoteLintInput, _ index: LintCorpusIndex) -> [LintEngine.Finding] {
        guard note.doc.template == nil, !note.doc.locked else { return [] }
        
        let threshold = Config.getInt("lint.oversized_words", default: 2000)
        let words = SectionEdit.wordCount(note.body)
        
        guard words >= threshold else { return [] }
        
        let sections = SectionEdit.sectionCount(note.body)
        
        return [
            .init(
                "\(words) words in \(sections) sections — one retrieval loads all of it; "
                    + "inspect shape with `query get \(note.nid) --toc`, read parts with --section"
            )
        ]
    }
    
    // MARK: - Private
}

struct GrowthUnboundedRule: NoteLintRule {
    // MARK: - Property
    let code = "growth-unbounded"
    let severity = LintEngine.Severity.warn
    
    private static let datedHeadingRegex = try! NSRegularExpression(
        pattern: #"^\d{4}-\d{2}-\d{2}"#
    )
    private static let periodIdRegex = try! NSRegularExpression(
        pattern: #"-\d{6}(-\d{2,6})?(-(am|pm))?$"#
    )
    
    // MARK: - Initializer
    // MARK: - Public
    func check(_ note: NoteLintInput, _ index: LintCorpusIndex) -> [LintEngine.Finding] {
        guard note.doc.template == nil, !note.doc.locked else { return [] }
        guard !Self.matches(Self.periodIdRegex, note.nid) else { return [] }
        
        let dated = note.document.sections.filter { section in
            Self.matches(Self.datedHeadingRegex, section.title)
        }
        let minEntries = Config.getInt("lint.growth_min_dated_sections", default: 8)
        
        guard dated.count >= minEntries else { return [] }
        
        return [
            .init(
                "\(dated.count) dated sections (\(SectionEdit.wordCount(note.body)) words) — "
                    + "append-only buffer, so size tracks time not subject; roll to a new period note "
                    + "and keep an index of periods"
            )
        ]
    }
    
    // MARK: - Private
    private static func matches(_ regex: NSRegularExpression, _ text: String) -> Bool {
        let nsText = text as NSString
        
        return regex.firstMatch(
            in: text,
            range: NSRange(location: 0, length: nsText.length)
        ) != nil
    }
}

struct EnrichThinRule: NoteDBLintRule {
    // MARK: - Property
    let code = "enrich-thin"
    let severity = LintEngine.Severity.warn
    
    private static let longIdentRegex = try! NSRegularExpression(pattern: #"[A-Za-z]{12,}"#)
    private static let camelHumpRegex = try! NSRegularExpression(pattern: #"[a-z][A-Z]"#)
    
    // MARK: - Initializer
    // MARK: - Public
    func check(_ scope: GRDBReadScope, note: NoteLintInput) throws -> [LintEngine.Finding] {
        let haystack = "\(note.doc.title)\n\(note.body)"
        
        guard hasHangul(haystack) else { return [] }
        
        let compounds = Self.hiddenCompounds(haystack)
        
        guard !compounds.isEmpty else { return [] }
        
        let active = try scope.run(CountActiveRetrievalTermsTransaction(noteId: note.nid))
        
        guard active == 0 else { return [] }
        
        let sample = compounds.prefix(5).joined(separator: ", ")
        let more = compounds.count > 5 ? " +\(compounds.count - 5) more" : ""
        
        return [
            .init(
                "Korean body + 0 active aliases + \(compounds.count) CamelCase identifier(s) unreachable by keyword search: \(sample)\(more)"
            )
        ]
    }
    
    // MARK: - Private
    private static func hiddenCompounds(_ text: String) -> [String] {
        let nsText = text as NSString
        var found: [String] = []
        var seen = Set<String>()
        
        longIdentRegex.enumerateMatches(
            in: text,
            range: NSRange(location: 0, length: nsText.length)
        ) { match, _, _ in
            guard let match else { return }
            
            let token = nsText.substring(with: match.range)
            let nsToken = token as NSString
            
            if camelHumpRegex.firstMatch(
                in: token,
                range: NSRange(location: 0, length: nsToken.length)
            ) != nil, seen.insert(token).inserted {
                found.append(token)
            }
        }
        
        return found
    }
}

struct TemplateDriftRule: NoteDBLintRule {
    // MARK: - Property
    let code = "template-drift"
    let severity = LintEngine.Severity.warn
    
    // MARK: - Initializer
    // MARK: - Public
    func check(_ scope: GRDBReadScope, note: NoteLintInput) throws -> [LintEngine.Finding] {
        guard let templateId = note.doc.template, !templateId.isEmpty else { return [] }
        
        guard let frame = try scope.run(LoadTemplateFrameTransaction(templateId: templateId)) else {
            return [.init("template note '\(templateId)' not found — cannot validate frame")]
        }
        
        if let violation = Template.validate(documentBody: note.body, frame: frame) {
            return [.init("body diverges from template '\(templateId)' frame: \(violation)")]
        }
        
        return []
    }
    
    // MARK: - Private
}

struct IsolatedNoteRule: CorpusDBLintRule {
    // MARK: - Property
    let code = "isolated"
    let severity = LintEngine.Severity.warn
    
    // MARK: - Initializer
    // MARK: - Public
    func check(_ scope: GRDBReadScope) throws -> [LintEngine.Finding] {
        try scope.run(FetchFragmentationRowsTransaction())
            .filter { row in row.linkN == 0 && row.entN == 0 && row.tagN <= 1 }
            .map { row in
                .init("no links, no entities, ≤1 tag — orphan", target: .note(row.nid))
            }
    }
    
    // MARK: - Private
}

struct FragmentUnlinkedRule: CorpusDBLintRule {
    // MARK: - Property
    let code = "fragment-unlinked"
    let severity = LintEngine.Severity.warn
    
    // MARK: - Initializer
    // MARK: - Public
    func check(_ scope: GRDBReadScope) throws -> [LintEngine.Finding] {
        var findings: [LintEngine.Finding] = []
        
        for family in try FamilyView.families(scope) {
            let unlinked = try FamilyView.unlinkedMembers(scope, family)
            
            guard !unlinked.isEmpty else { continue }
            
            let sample = unlinked.prefix(3).joined(separator: ", ")
            let more = unlinked.count > 3 ? " +\(unlinked.count - 3) more" : ""
            let name = family.stem ?? family.key
            
            findings.append(
                .init(
                    "`\(name)` family: \(unlinked.count)/\(family.members.count) members "
                        + "hold no deliberate link to a sibling or to "
                        + (family.hasIndex ? "the `\(name)` index" : "an index note")
                        + " — a split without links is knowledge lost, not organized (\(sample)\(more))",
                    target: .note(family.key),
                    key: "unlinked:\(name)"
                )
            )
        }
        
        return findings
    }
    
    // MARK: - Private
}

struct GistMissingRule: CorpusDBLintRule {
    // MARK: - Property
    let code = "gist-missing"
    let severity = LintEngine.Severity.warn
    
    // MARK: - Initializer
    // MARK: - Public
    func check(_ scope: GRDBReadScope) throws -> [LintEngine.Finding] {
        try FamilyView.families(scope).compactMap { family in
            guard !family.hasIndex, let stem = family.stem else { return nil }
            
            return .init(
                "`\(stem)` family (\(family.members.count) members) has no index note — "
                    + "분화는 아래로 낱개·위로 요지가 짝이다. 진입점이 없으면 어느 낱개로 들어갈지 "
                    + "정할 수 없다: `\(stem)` 요지를 세우고 낱개가 그것을 참조하게 한다",
                target: .note(family.key),
                key: "gist:\(stem)"
            )
        }
    }
    
    // MARK: - Private
}

// Tags are the only classification a note has, so one tag means one way in.
// A note that is otherwise connected but carries a single label is reachable
// from one context only — that is under-classification, not minimalism.
struct SingleTagRule: CorpusDBLintRule {
    // MARK: - Property
    let code = "tag-underclassified"
    let severity = LintEngine.Severity.warn
    
    // MARK: - Initializer
    // MARK: - Public
    func check(_ scope: GRDBReadScope) throws -> [LintEngine.Finding] {
        try scope.run(FetchFragmentationRowsTransaction())
            .filter { row in
                !(row.linkN == 0 && row.entN == 0 && row.tagN <= 1) && row.tagN <= 1
            }
            .map { row in
                .init("a single tag — one label is one way in", target: .note(row.nid))
            }
    }
    
    // MARK: - Private
}

struct TagNearDuplicateRule: CorpusDBLintRule {
    // MARK: - Property
    let code = "tag-near-duplicate"
    let severity = LintEngine.Severity.warn
    
    // MARK: - Initializer
    // MARK: - Public
    func check(_ scope: GRDBReadScope) throws -> [LintEngine.Finding] {
        let counts = try scope.run(FetchTagUsageTransaction())
        var findings: [LintEngine.Finding] = []
        
        for leftIndex in 0..<counts.count {
            let left = counts[leftIndex]
            
            for rightIndex in (leftIndex + 1)..<counts.count {
                let right = counts[rightIndex]
                
                guard max(left.tag.count, right.tag.count) >= 4 else { continue }
                guard withinEdit1(left.tag, right.tag) else { continue }
                guard left.tag.filter({ character in !character.isNumber })
                    != right.tag.filter({ character in !character.isNumber })
                else {
                    continue
                }
                
                let (more, fewer) = left.c >= right.c ? (left, right) : (right, left)
                let pair = left.tag < right.tag
                    ? "\(left.tag)|\(right.tag)"
                    : "\(right.tag)|\(left.tag)"
                
                findings.append(
                    .init(
                        "tags '\(more.tag)'(\(more.c)) · '\(fewer.tag)'(\(fewer.c)) are edit-distance 1 apart",
                        target: .corpus("tag-pair:\(pair)")
                    )
                )
            }
        }
        
        return findings
    }
    
    // MARK: - Private
}

func withinEdit1(_ left: String, _ right: String) -> Bool {
    if left == right { return false }
    
    let leftCharacters = Array(left)
    let rightCharacters = Array(right)
    let leftCount = leftCharacters.count
    let rightCount = rightCharacters.count
    
    if abs(leftCount - rightCount) > 1 { return false }
    
    if leftCount == rightCount {
        var different = 0
        
        for index in 0..<leftCount where leftCharacters[index] != rightCharacters[index] {
            different += 1
            
            if different > 1 { return false }
        }
        
        return different == 1
    }
    
    let (shorter, longer) = leftCount < rightCount
        ? (leftCharacters, rightCharacters)
        : (rightCharacters, leftCharacters)
    var shortIndex = 0
    var longIndex = 0
    var skipped = false
    
    while shortIndex < shorter.count && longIndex < longer.count {
        if shorter[shortIndex] == longer[longIndex] {
            shortIndex += 1
            longIndex += 1
        } else {
            if skipped { return false }
            
            skipped = true
            longIndex += 1
        }
    }
    
    return true
}

private func hasHangul(_ text: String) -> Bool {
    let nsText = text as NSString
    
    return hangulRegex.firstMatch(
        in: text,
        range: NSRange(location: 0, length: nsText.length)
    ) != nil
}

