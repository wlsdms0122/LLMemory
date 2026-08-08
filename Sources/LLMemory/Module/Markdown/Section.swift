//
//  Section.swift
//  LLMemory
//
//  Created by JSilver on 8/7/26.
//

import Foundation

enum SectionEdit {
    enum InsertAnchor {
        case after(SectionPath)
        case before(SectionPath)
        case atEnd
    }
    
    struct Section: Equatable {
        // MARK: - Property
        let level: Int
        let title: String
        let lineStart: Int
        let lineEnd: Int
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    struct SectionPath: Equatable, Hashable {
        struct Part: Equatable, Hashable {
            // MARK: - Property
            let level: Int
            let title: String
            
            // MARK: - Initializer
            // MARK: - Public
            // MARK: - Private
        }
        
        // MARK: - Property
        let parts: [Part]
        
        // MARK: - Initializer
        // MARK: - Public
        func display() -> String {
            parts
                .map { part in "\(String(repeating: "#", count: part.level)) \(part.title)" }
                .joined(separator: " > ")
        }
        
        // MARK: - Private
    }
    
    struct PathCollision: Equatable {
        // MARK: - Property
        let path: SectionPath
        let lines: [Int]
        
        // MARK: - Initializer
        // MARK: - Public
        func display() -> String {
            "\(path.display()) @ lines \(intListLiteral(lines))"
        }
        
        // MARK: - Private
    }
    
    struct FenceScan {
        // MARK: - Property
        let mask: [Bool]
        let unclosedOpen: Int?
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    struct SectionRow: Equatable {
        // MARK: - Property
        let path: String
        let text: String
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    // MARK: - Property
    static let preambleToken = "(preamble)"
    
    private static let headingRegex: NSRegularExpression = try! NSRegularExpression(
        pattern: #"^(#{1,6})\s+(.+?)\s*$"#,
        options: []
    )
    
    private static let pathSepRegex: NSRegularExpression = try! NSRegularExpression(
        pattern: #"\s*>\s*(?=#{1,6}\s)"#,
        options: []
    )
    
    private static let fenceRegex: NSRegularExpression = try! NSRegularExpression(
        pattern: #"^ {0,3}((?:`{3,})|(?:~{3,}))(.*)$"#,
        options: []
    )
    
    private static let parsePathHint = ###"(hint: section path must start with a markdown heading marker (#..######), e.g. "## 제목" or "## A > ### B" — see `ops describe patch_section`)"###
    
    // MARK: - Initializer
    // MARK: - Public
    static func parsePath(_ path: String) throws -> SectionPath {
        let nsPath = path as NSString
        let separators = pathSepRegex.matches(
            in: path,
            range: NSRange(location: 0, length: nsPath.length)
        )
        var segments: [String] = []
        var cursor = 0
        
        for separator in separators {
            segments.append(
                nsPath.substring(
                    with: NSRange(location: cursor, length: separator.range.location - cursor)
                )
            )
            cursor = separator.range.location + separator.range.length
        }
        
        segments.append(nsPath.substring(from: cursor))
        segments = segments.map { segment in segment.trimmingCharacters(in: .whitespaces) }
        
        var parts: [SectionPath.Part] = []
        
        for segment in segments {
            if segment.isEmpty {
                throw SectionError.parse("empty segment in path: '\(path)' \(parsePathHint)")
            }
            
            let nsSegment = segment as NSString
            
            guard let match = headingRegex.firstMatch(
                in: segment,
                range: NSRange(location: 0, length: nsSegment.length)
            ) else {
                throw SectionError.parse(
                    "invalid heading in path segment: '\(segment)' \(parsePathHint)"
                )
            }
            
            let level = nsSegment.substring(with: match.range(at: 1)).count
            let title = nsSegment.substring(with: match.range(at: 2))
                .trimmingCharacters(in: .whitespaces)
            parts.append(.init(level: level, title: title))
        }
        
        if parts.isEmpty {
            throw SectionError.parse("empty section path: '\(path)'")
        }
        
        for index in 1..<parts.count {
            if parts[index].level <= parts[index - 1].level {
                throw SectionError.parse("path levels must strictly increase: '\(path)'")
            }
        }
        
        return SectionPath(parts: parts)
    }
    
    static func scanFences(_ lines: [String]) -> FenceScan {
        var mask = [Bool](repeating: false, count: lines.count)
        var openLine: Int? = nil
        var openChar: Character = "`"
        var openLength = 0
        
        for (index, line) in lines.enumerated() {
            guard couldBeFence(line) else {
                mask[index] = openLine != nil
                continue
            }
            
            let nsLine = line as NSString
            let match = fenceRegex.firstMatch(
                in: line,
                range: NSRange(location: 0, length: nsLine.length)
            )
            
            guard let match else {
                mask[index] = openLine != nil
                continue
            }
            
            let run = nsLine.substring(with: match.range(at: 1))
            let rest = nsLine.substring(with: match.range(at: 2))
            let character = run.first!
            
            if openLine == nil {
                if character == "`" && rest.contains("`") {
                    mask[index] = false
                    continue
                }
                
                openLine = index
                openChar = character
                openLength = run.count
                mask[index] = true
            } else {
                mask[index] = true
                
                let bare = rest.trimmingCharacters(in: .whitespaces).isEmpty
                
                if character == openChar && run.count >= openLength && bare {
                    openLine = nil
                }
            }
        }
        
        return FenceScan(mask: mask, unclosedOpen: openLine)
    }
    
    static func fenceMask(_ lines: [String]) -> [Bool] {
        scanFences(lines).mask
    }
    
    static func splitSections(_ body: String) -> [Section] {
        let lines = body.unicodeLines()
        let fence = fenceMask(lines)
        var headings: [(Int, Int, String)] = []
        
        for (index, line) in lines.enumerated() {
            if fence[index] { continue }
            
            let nsLine = line as NSString
            
            if let match = headingRegex.firstMatch(
                in: line,
                range: NSRange(location: 0, length: nsLine.length)
            ) {
                let level = nsLine.substring(with: match.range(at: 1)).count
                let title = nsLine.substring(with: match.range(at: 2))
                    .trimmingCharacters(in: .whitespaces)
                headings.append((index, level, title))
            }
        }
        
        var sections: [Section] = []
        
        for (index, (start, level, title)) in headings.enumerated() {
            var end = lines.count
            
            for next in (index + 1)..<headings.count {
                if headings[next].1 <= level {
                    end = headings[next].0
                    break
                }
            }
            
            sections.append(Section(level: level, title: title, lineStart: start, lineEnd: end))
        }
        
        return sections
    }
    
    static func findSection(_ body: String, path: SectionPath) throws -> Section {
        let sections = splitSections(body)
        let candidates = findMatches(sections: sections, path: path)
        
        if candidates.isEmpty {
            throw SectionError.notFound("section not found: \(path.display())")
        }
        
        if candidates.count > 1 {
            let lines = candidates.map { section in section.lineStart + 1 }
            
            throw SectionError.ambiguous(
                "ambiguous section path: \(path.display()) (matched \(candidates.count) sections @ lines \(intListLiteral(lines)))"
            )
        }
        
        return candidates[0]
    }
    
    static func descendantSections(_ body: String, of section: Section) -> [Section] {
        splitSections(body)
            .filter { child in
                child.lineStart > section.lineStart && child.lineEnd <= section.lineEnd
            }
            .sorted { lhs, rhs in lhs.lineStart < rhs.lineStart }
    }
    
    static func directBodyEnd(of section: Section, within sections: [Section]) -> Int {
        sections.first { child in
            child.lineStart > section.lineStart && child.lineEnd <= section.lineEnd
        }?.lineStart ?? section.lineEnd
    }
    
    static func directBodyEnd(_ body: String, of section: Section) -> Int {
        directBodyEnd(of: section, within: splitSections(body))
    }
    
    static func replace(
        _ body: String,
        path: SectionPath,
        newContent: String,
        subtree: Bool = false
    ) throws -> String {
        let section = try findSection(body, path: path)
        var lines = body.unicodeLines()
        let headingLine = lines[section.lineStart]
        var newBlock = [headingLine]
        let trimmedContent = newContent.trimmingTrailingNewlines()
        
        if !trimmedContent.isEmpty { newBlock.append(trimmedContent) }
        
        let bodyEnd = subtree ? section.lineEnd : directBodyEnd(body, of: section)
        lines = splice(lines, start: section.lineStart, end: bodyEnd, with: newBlock)
        
        return lines.joined(separator: "\n") + "\n"
    }
    
    static func append(
        _ body: String,
        path: SectionPath,
        content: String,
        subtree: Bool = false
    ) throws -> String {
        let section = try findSection(body, path: path)
        var lines = body.unicodeLines()
        let insertAt = subtree ? section.lineEnd : directBodyEnd(body, of: section)
        let block = contentLines(content)
        lines.insert(contentsOf: block, at: insertAt)
        
        return lines.joined(separator: "\n") + "\n"
    }
    
    static func prepend(_ body: String, path: SectionPath, content: String) throws -> String {
        let section = try findSection(body, path: path)
        var lines = body.unicodeLines()
        let insertAt = section.lineStart + 1
        let block = contentLines(content)
        lines.insert(contentsOf: block, at: insertAt)
        
        return lines.joined(separator: "\n") + "\n"
    }
    
    static func remove(
        _ body: String,
        path: SectionPath,
        subtree: Bool = false
    ) throws -> String {
        let section = try findSection(body, path: path)
        
        if !subtree {
            let children = descendantSections(body, of: section)
            
            if !children.isEmpty {
                let names = children
                    .map { child in headingLabel(child) }
                    .joined(separator: ", ")
                
                throw SectionError.guarded(
                    "remove '\(headingLabel(section))' 는 하위 섹션 \(children.count)개를 함께 삭제함: [\(names)]. "
                    + "의도한 거면 op 에 \"subtree\": true 를 명시."
                )
            }
        }
        
        var lines = body.unicodeLines()
        lines.removeSubrange(section.lineStart..<section.lineEnd)
        
        return lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"
    }
    
    static func applyPatch(
        _ body: String,
        section: String,
        action: String,
        content: String,
        subtree: Bool
    ) throws -> String {
        if section == preambleToken {
            switch action {
            case "replace":
                return replacePreamble(body, newContent: content)
            
            case "append":
                return appendPreamble(body, content: content)
            
            case "prepend":
                return prependPreamble(body, content: content)
            
            case "remove":
                return removePreamble(body)
            
            default:
                throw SectionError.parse("invalid action: \(action)")
            }
        }
        
        let path = try parsePath(section)
        
        switch action {
        case "replace":
            return try replace(body, path: path, newContent: content, subtree: subtree)
        
        case "append":
            return try append(body, path: path, content: content, subtree: subtree)
        
        case "prepend":
            return try prepend(body, path: path, content: content)
        
        case "remove":
            return try remove(body, path: path, subtree: subtree)
        
        default:
            throw SectionError.parse("invalid action: \(action)")
        }
    }
    
    static func replacePreamble(_ body: String, newContent: String) -> String {
        let lines = body.unicodeLines()
        let trimmedContent = newContent.trimmingTrailingNewlines()
        let block = trimmedContent.isEmpty ? [] : trimmedContent.unicodeLines()
        let spliced = splice(lines, start: 0, end: preambleEnd(body, lines), with: block)
        
        return spliced.isEmpty ? "" : spliced.joined(separator: "\n") + "\n"
    }
    
    static func appendPreamble(_ body: String, content: String) -> String {
        var lines = body.unicodeLines()
        lines.insert(contentsOf: contentLines(content), at: preambleEnd(body, lines))
        
        return lines.joined(separator: "\n") + "\n"
    }
    
    static func prependPreamble(_ body: String, content: String) -> String {
        var lines = body.unicodeLines()
        lines.insert(contentsOf: contentLines(content), at: 0)
        
        return lines.joined(separator: "\n") + "\n"
    }
    
    static func removePreamble(_ body: String) -> String {
        let lines = body.unicodeLines()
        let remaining = Array(lines[preambleEnd(body, lines)...])
        
        return remaining.isEmpty ? "" : remaining.joined(separator: "\n") + "\n"
    }
    
    static func insert(
        _ body: String,
        newSectionText: String,
        anchor: InsertAnchor
    ) throws -> String {
        var lines = body.unicodeLines()
        let insertAt: Int
        
        switch anchor {
        case .atEnd:
            insertAt = lines.count
        
        case .after(let path):
            let section = try findSection(body, path: path)
            insertAt = section.lineEnd
        
        case .before(let path):
            let section = try findSection(body, path: path)
            insertAt = section.lineStart
        }
        
        let block = contentLines(newSectionText)
        lines.insert(contentsOf: block, at: insertAt)
        
        return lines.joined(separator: "\n") + "\n"
    }
    
    static func rename(_ body: String, path: SectionPath, newTitle: String) throws -> String {
        let section = try findSection(body, path: path)
        let trimmed = newTitle.trimmingCharacters(in: .whitespaces)
        
        if trimmed.isEmpty {
            throw SectionError.parse("new_title empty")
        }
        
        var lines = body.unicodeLines()
        lines[section.lineStart] = "\(String(repeating: "#", count: section.level)) \(trimmed)"
        
        return lines.joined(separator: "\n") + "\n"
    }
    
    static func resolveDisjoint(_ body: String, paths: [SectionPath]) throws -> [Section] {
        let sections = try paths.map { path in try findSection(body, path: path) }
        let byStart = sections.sorted { lhs, rhs in lhs.lineStart < rhs.lineStart }
        
        for index in byStart.indices.dropFirst() {
            let previous = byStart[index - 1]
            let current = byStart[index]
            
            if current.lineStart < previous.lineEnd {
                throw SectionError.guarded(
                    "overlapping/duplicate sections requested: '\(headingLabel(previous))' and "
                    + "'\(headingLabel(current))' — a section can't be carved out alongside its parent "
                    + "or a duplicate of itself (each line belongs to exactly one piece)."
                )
            }
        }
        
        return sections
    }
    
    static func extract(
        _ body: String,
        paths: [SectionPath]
    ) throws -> (extracted: String, remaining: String) {
        let sections = try resolveDisjoint(body, paths: paths)
        let byStart = sections.sorted { lhs, rhs in lhs.lineStart < rhs.lineStart }
        var lines = body.unicodeLines()
        let chunks = byStart.map { section in
            Array(lines[section.lineStart..<section.lineEnd])
        }
        
        for section in byStart.reversed() {
            lines.removeSubrange(section.lineStart..<section.lineEnd)
        }
        
        var extracted = chunks.flatMap { chunk in chunk }.joined(separator: "\n")
        
        if !extracted.isEmpty { extracted += "\n" }
        
        var remaining = lines.joined(separator: "\n")
        
        if !remaining.isEmpty { remaining += "\n" }
        
        return (extracted, remaining)
    }
    
    static func sectionRows(_ body: String) -> (preamble: String, rows: [SectionRow]) {
        let lines = body.unicodeLines()
        let sections = splitSections(body)
        let preambleEnd = sections.first?.lineStart ?? lines.count
        let preamble = lines[..<preambleEnd].joined(separator: "\n")
        var stack: [Section] = []
        var rows: [SectionRow] = []
        
        for section in sections {
            while let top = stack.last, top.level >= section.level { stack.removeLast() }
            
            stack.append(section)
            
            let path = stack
                .map { entry in "\(String(repeating: "#", count: entry.level)) \(entry.title)" }
                .joined(separator: " > ")
            let bodyEnd = directBodyEnd(of: section, within: sections)
            let text = lines[section.lineStart..<bodyEnd].joined(separator: "\n")
            
            rows.append(SectionRow(path: path, text: text))
        }
        
        return (preamble, rows)
    }
    
    static func subtreeText(_ body: String, path: SectionPath) throws -> String {
        let section = try findSection(body, path: path)
        
        return body.unicodeLines()[section.lineStart..<section.lineEnd].joined(separator: "\n")
    }
    
    static func findPathCollisions(_ body: String) -> [PathCollision] {
        let sections = splitSections(body)
        
        if sections.isEmpty { return [] }
        
        func parentOf(_ index: Int) -> Int? {
            let section = sections[index]
            var best: Int? = nil
            
            for (candidate, parent) in sections.enumerated() {
                if candidate == index { continue }
                
                if parent.lineStart < section.lineStart && parent.lineEnd >= section.lineEnd {
                    if best == nil || sections[best!].level < parent.level {
                        best = candidate
                    }
                }
            }
            
            return best
        }
        
        struct Key: Hashable {
            let parent: Int?
            let level: Int
            let title: String
        }
        
        var groups: [Key: [Int]] = [:]
        var keyOrder: [Key] = []
        
        for (index, section) in sections.enumerated() {
            let key = Key(parent: parentOf(index), level: section.level, title: section.title)
            
            if groups[key] == nil { keyOrder.append(key) }
            
            groups[key, default: []].append(index)
        }
        
        var collisions: [PathCollision] = []
        
        for key in keyOrder {
            let indices = groups[key] ?? []
            
            if indices.count < 2 { continue }
            
            var chain: [SectionPath.Part] = []
            var cursor: Int? = key.parent
            
            while let current = cursor {
                chain.append(
                    .init(level: sections[current].level, title: sections[current].title)
                )
                
                var outer: Int? = nil
                let currentSection = sections[current]
                
                for (candidate, parent) in sections.enumerated() {
                    if candidate == current { continue }
                    
                    if parent.lineStart < currentSection.lineStart
                        && parent.lineEnd >= currentSection.lineEnd {
                        if outer == nil || sections[outer!].level < parent.level {
                            outer = candidate
                        }
                    }
                }
                
                cursor = outer
            }
            
            var parts: [SectionPath.Part] = Array(chain.reversed())
            parts.append(.init(level: key.level, title: key.title))
            
            let path = SectionPath(parts: parts)
            let lines = indices.map { index in sections[index].lineStart + 1 }
            
            collisions.append(PathCollision(path: path, lines: lines))
        }
        
        collisions.sort { lhs, rhs in (lhs.lines.first ?? 0) < (rhs.lines.first ?? 0) }
        
        return collisions
    }
    
    static func assertResolvable(_ body: String, noteId: String = "") throws {
        let collisions = findPathCollisions(body)
        
        if !collisions.isEmpty {
            throw SectionError.invariant(collisions, noteId: noteId)
        }
    }
    
    static func wordCount(_ body: String) -> Int {
        let regex = try! NSRegularExpression(pattern: "\\S+", options: [])
        
        return regex.numberOfMatches(
            in: body,
            range: NSRange(location: 0, length: (body as NSString).length)
        )
    }
    
    static func sectionCount(_ body: String) -> Int {
        splitSections(body).count
    }
    
    // MARK: - Private
    private static func couldBeFence(_ line: String) -> Bool {
        var spaces = 0
        
        for character in line {
            if character == " " {
                spaces += 1
                
                if spaces > 3 { return false }
                
                continue
            }
            
            return character == "`" || character == "~"
        }
        
        return false
    }
    
    private static func findMatches(sections: [Section], path: SectionPath) -> [Section] {
        guard let first = path.parts.first else { return [] }
        
        let matches = sections.filter { section in
            section.level == first.level && section.title == first.title
        }
        
        if path.parts.count == 1 { return matches }
        
        var resolved: [Section] = []
        
        for parent in matches {
            var currentParent = parent
            var ok = true
            
            for part in path.parts.dropFirst() {
                let children = sections.filter { child in
                    child.lineStart > currentParent.lineStart
                        && child.lineEnd <= currentParent.lineEnd
                        && child.level == part.level
                        && child.title == part.title
                }
                
                if children.isEmpty {
                    ok = false
                    break
                }
                
                if children.count > 1 {
                    return children
                }
                
                currentParent = children[0]
            }
            
            if ok { resolved.append(currentParent) }
        }
        
        return resolved
    }
    
    private static func headingLabel(_ section: Section) -> String {
        "\(String(repeating: "#", count: section.level)) \(section.title)"
    }
    
    private static func preambleEnd(_ body: String, _ lines: [String]) -> Int {
        splitSections(body).first?.lineStart ?? lines.count
    }
    
    private static func splice(
        _ lines: [String],
        start: Int,
        end: Int,
        with newBlock: [String]
    ) -> [String] {
        Array(lines[..<start]) + newBlock + Array(lines[end...])
    }
    
    private static func contentLines(_ text: String) -> [String] {
        let trimmed = text.trimmingTrailingNewlines()
        
        return trimmed.isEmpty ? [""] : trimmed.unicodeLines()
    }
}

enum SectionError: Error, CustomStringConvertible {
    case parse(String)
    case notFound(String)
    case ambiguous(String)
    case guarded(String)
    case invariant([SectionEdit.PathCollision], noteId: String)
    
    var description: String {
        switch self {
        case .parse(let message), .notFound(let message), .ambiguous(let message),
            .guarded(let message):
            return message
        
        case .invariant(let collisions, let noteId):
            let details = collisions.map { collision in collision.display() }
                .joined(separator: "; ")
            let prefix = noteId.isEmpty ? "" : "note \(noteId): "
            
            return "\(prefix)section path collision: \(details)"
        }
    }
}
