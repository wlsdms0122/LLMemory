//
//  LintLinePatternRule.swift
//  LLMemory
//
//  Created by JSilver on 8/8/26.
//

import Foundation

struct LintLinePatternRule: LintDocumentRule {
    // MARK: - Property
    let code: String
    let severity: LintSeverity
    let pattern: NSRegularExpression
    let message: @Sendable (Int, String) -> String
    
    private let engine = LintEngine()

    // MARK: - Initializer
    init(
        code: String,
        severity: LintSeverity,
        pattern: String,
        message: @escaping @Sendable (Int, String) -> String
    ) {
        self.code = code
        self.severity = severity
        self.pattern = try! NSRegularExpression(pattern: pattern)
        self.message = message
    }
    
    // MARK: - Public
    func check(_ doc: LintDocument) -> [LintFinding] {
        let hits = doc.contentLineIndices().filter { index in
            let nsLine = doc.lines[index] as NSString
            
            return pattern.firstMatch(
                in: doc.lines[index],
                range: NSRange(location: 0, length: nsLine.length)
            ) != nil
        }
        
        return engine.groupBySubject(hits) { index in
            doc.lines[index].trimmingCharacters(in: .whitespaces)
        }
        .map { text, lineIndices in
            let lineNumbers = lineIndices.map { index in index + 1 }
            
            return .init(
                message(lineNumbers[0], doc.lines[lineIndices[0]])
                    + engine.repeatSuffix(lineNumbers),
                key: "line:\(text)"
            )
        }
    }
    
    // MARK: - Private
}
