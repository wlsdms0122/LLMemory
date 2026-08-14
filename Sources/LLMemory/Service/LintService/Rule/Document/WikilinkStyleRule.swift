//
//  WikilinkStyleRule.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation

struct WikilinkStyleRule: LintDocumentRule {
    // MARK: - Property
    let code = "wikilink-style"
    let severity = LintSeverity.warn
    
    private static let wikilinkRegex = try! NSRegularExpression(
        pattern: #"\[\[([a-z0-9][a-z0-9-]*)\]\]"#
    )
    
    private let repeated = RepeatedFinding()

    // MARK: - Initializer
    // MARK: - Public
    func check(_ doc: LintDocument) -> [LintFinding] {
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
        
        return repeated.groupBySubject(hits, by: \.id).map { id, occurrences in
            let lines = occurrences.map(\.line)
            
            return .init(
                "wikilink `[[\(id)]]` (line \(lines[0])) — use a backtick reference `\(id)` instead"
                    + repeated.repeatSuffix(lines),
                key: "wikilink:\(id)"
            )
        }
    }
    
    // MARK: - Private
}
