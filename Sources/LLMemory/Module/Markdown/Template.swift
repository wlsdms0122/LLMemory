//
//  Template.swift
//  LLMemory
//
//  Created by JSilver on 8/7/26.
//

import Foundation

public struct Template: Sendable {
    // MARK: - Property
    private static let leadingMarkerRegex = try! NSRegularExpression(
        pattern: #"^\s*(?:[0-9]+[.)]?|[①-⑳]|[-*•◦])\s+"#
    )
    
    private let sectionEdit = SectionEdit()

    // MARK: - Initializer
    // MARK: - Public
    public func parseFrame(_ body: String) -> [TemplateFrameNode] {
        parseTree(body, withGuides: true)
    }
    
    func normalize(_ title: String) -> String {
        var normalized = title.precomposedStringWithCanonicalMapping
        let nsTitle = normalized as NSString
        
        if let match = Self.leadingMarkerRegex.firstMatch(
            in: normalized,
            range: NSRange(location: 0, length: nsTitle.length)
        ), match.range.location == 0 {
            normalized = nsTitle.substring(from: match.range.length)
        }
        
        return normalized.trimmingCharacters(in: .whitespaces).lowercased()
    }
    
    func parseTree(_ body: String, withGuides: Bool) -> [TemplateFrameNode] {
        let lines = body.unicodeLines()
        let sections = sectionEdit.splitSections(body)
        
        if sections.isEmpty { return [] }
        
        func parentOf(_ index: Int) -> Int? {
            let section = sections[index]
            var best: Int? = nil
            
            for (candidate, parent) in sections.enumerated() where candidate != index {
                if parent.lineStart < section.lineStart && parent.lineEnd >= section.lineEnd {
                    if best == nil || sections[best!].level < parent.level { best = candidate }
                }
            }
            
            return best
        }
        
        var childIndices: [Int: [Int]] = [:]
        var roots: [Int] = []
        
        for index in sections.indices {
            if let parent = parentOf(index) {
                childIndices[parent, default: []].append(index)
            } else {
                roots.append(index)
            }
        }
        
        func guideText(_ index: Int) -> String {
            guard withGuides else { return "" }
            
            let section = sections[index]
            let children = childIndices[index] ?? []
            let end = children.map { child in sections[child].lineStart }.min() ?? section.lineEnd
            let start = section.lineStart + 1
            
            if start >= end { return "" }
            
            return lines[start..<end].joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        func build(_ index: Int) -> TemplateFrameNode {
            let section = sections[index]
            let children = (childIndices[index] ?? []).sorted { lhs, rhs in
                sections[lhs].lineStart < sections[rhs].lineStart
            }
            
            return TemplateFrameNode(
                level: section.level,
                title: section.title,
                norm: normalize(section.title),
                guide: guideText(index),
                children: children.map(build)
            )
        }
        
        return roots
            .sorted { lhs, rhs in sections[lhs].lineStart < sections[rhs].lineStart }
            .map(build)
    }
    
    func validate(documentBody: String, frame: [TemplateFrameNode]) -> String? {
        let documentTree = parseTree(documentBody, withGuides: false)
        
        return matchLevel(frame: frame, doc: documentTree, pathPrefix: "")
    }
    
    func scaffold(_ frame: [TemplateFrameNode]) -> String {
        var lines: [String] = []
        
        func emit(_ nodes: [TemplateFrameNode]) {
            for node in nodes {
                lines.append(headingLabel(node))
                lines.append("")
                emit(node.children)
            }
        }
        
        emit(frame)
        
        while lines.last == "" { lines.removeLast() }
        
        return lines.joined(separator: "\n")
    }
    
    // MARK: - Private
    private func headingLabel(_ node: TemplateFrameNode) -> String {
        "\(String(repeating: "#", count: node.level)) \(node.title)"
    }
    
    private func matchLevel(
        frame: [TemplateFrameNode],
        doc: [TemplateFrameNode],
        pathPrefix: String
    ) -> String? {
        if frame.isEmpty { return nil }
        
        var seenNorm = Set<String>()
        
        for node in frame where !seenNorm.insert(node.norm).inserted {
            return "템플릿 frame 오류: 같은 레벨에 중복 섹션 '\(pathPrefix)\(headingLabel(node))' — 제목을 구분하라"
        }
        
        var matched: [Int] = []
        
        for documentNode in doc {
            guard let frameIndex = frame.firstIndex(where: { node in
                node.level == documentNode.level && node.title == documentNode.title
            }) else {
                if let near = frame.first(where: { node in node.norm == documentNode.norm }) {
                    return "외래 섹션: '\(pathPrefix)\(headingLabel(documentNode))' — frame 은 '\(pathPrefix)\(headingLabel(near))' (레벨·원문 완전일치 필요)"
                }
                
                return "외래 섹션: '\(pathPrefix)\(headingLabel(documentNode))' 가 템플릿 frame 에 없음"
            }
            
            matched.append(frameIndex)
        }
        
        var position = 1
        
        while position < matched.count {
            if matched[position] < matched[position - 1] {
                return "섹션 순서가 frame 과 다름: '\(pathPrefix)\(headingLabel(doc[position]))'"
            }
            
            position += 1
        }
        
        var counts = [Int](repeating: 0, count: frame.count)
        
        for frameIndex in matched { counts[frameIndex] += 1 }
        
        for (frameIndex, node) in frame.enumerated() {
            if counts[frameIndex] == 0 {
                return "필수 섹션 누락: '\(pathPrefix)\(headingLabel(node))'"
            }
            
            if counts[frameIndex] > 1 {
                return "필수 섹션 중복: '\(pathPrefix)\(headingLabel(node))' (\(counts[frameIndex])개)"
            }
        }
        
        for (documentIndex, documentNode) in doc.enumerated() {
            let frameNode = frame[matched[documentIndex]]
            let childPrefix = "\(pathPrefix)\(headingLabel(documentNode)) > "
            
            if let violation = matchLevel(
                frame: frameNode.children,
                doc: documentNode.children,
                pathPrefix: childPrefix
            ) {
                return violation
            }
        }
        
        return nil
    }
}
