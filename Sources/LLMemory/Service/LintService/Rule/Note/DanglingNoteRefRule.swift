//
//  DanglingNoteRefRule.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation

struct DanglingNoteRefRule: NoteLintRule {
    // MARK: - Property
    let code = "dangling-note-ref"
    let severity = LintSeverity.warn
    
    private static let tokenRegex = try! NSRegularExpression(
        pattern: #"`([a-z][a-z0-9-]{3,})`"#
    )
    private static let wikilinkRegex = try! NSRegularExpression(
        pattern: #"\[\[([a-z][a-z0-9-]{3,})\]\]"#
    )
    
    private let distance = EditDistance()

    // MARK: - Initializer
    // MARK: - Public
    func check(_ note: NoteLintInput, _ index: LintCorpusIndex) -> [LintFinding] {
        var seen = Set<String>()
        var findings: [LintFinding] = []
        
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
                    
                    guard let nearest = nearestId(
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
    
    func nearestId(
        _ token: String,
        _ ids: Set<String>,
        excluding nid: String
    ) -> String? {
        var edit1: [String] = []
        var extensions: [String] = []
        
        for id in ids where id != nid {
            if distance.withinOne(id, token) {
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
