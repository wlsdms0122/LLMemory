//
//  LintEngine.swift
//  LLMemory
//
//  Created by JSilver on 8/7/26.
//

import Foundation

enum LintEngine {
    enum Severity: String {
        case error
        case warn
    }
    
    struct Finding {
        // MARK: - Property
        let message: String
        let target: LintTarget?
        let key: String?
        
        // MARK: - Initializer
        init(_ message: String, target: LintTarget? = nil, key: String? = nil) {
            self.message = message
            self.target = target
            self.key = key
        }
        
        // MARK: - Public
        // MARK: - Private
    }
    
    struct Section {
        // MARK: - Property
        let level: Int
        let title: String
        let lineStart: Int
        let lineEnd: Int
        let path: String
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    struct Document {
        // MARK: - Property
        let id: String
        let lines: [String]
        let sections: [Section]
        let inFence: [Bool]
        let unclosedFence: Int?
        
        // MARK: - Initializer
        // MARK: - Public
        func contentLineIndices() -> [Int] {
            lines.indices.filter { index in !inFence[index] }
        }
        
        // MARK: - Private
    }
    
    struct Output {
        // MARK: - Property
        let severity: Severity
        let code: String
        let message: String
        let target: LintTarget
        let key: String?
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Public
    static func groupBySubject<Item, Subject: Hashable>(
        _ items: [Item],
        by subject: (Item) -> Subject
    ) -> [(subject: Subject, items: [Item])] {
        var order: [Subject] = []
        var bucket: [Subject: [Item]] = [:]
        
        for item in items {
            let key = subject(item)
            
            if bucket[key] == nil { order.append(key) }
            
            bucket[key, default: []].append(item)
        }
        
        return order.map { key in (key, bucket[key]!) }
    }
    
    static func repeatSuffix(_ lineNumbers: [Int]) -> String {
        guard lineNumbers.count > 1 else { return "" }
        
        let rest = lineNumbers.dropFirst().map(String.init).joined(separator: ", ")
        
        return " (+\(lineNumbers.count - 1) more at line\(lineNumbers.count > 2 ? "s" : "") \(rest))"
    }
    
    static func run(_ rules: [any LintDocumentRule], over doc: Document) -> [Output] {
        rules.flatMap { rule in
            rule.check(doc).map { finding in
                Output(
                    severity: rule.severity,
                    code: rule.code,
                    message: finding.message,
                    target: finding.target ?? .note(doc.id),
                    key: finding.key
                )
            }
        }
    }
    
    // MARK: - Private
}
