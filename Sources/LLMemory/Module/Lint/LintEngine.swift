//
//  LintEngine.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation

// Runs document rules over one parsed note and stamps each finding with the
// rule that produced it. It knows nothing about which rules exist — the
// catalog is handed in, so a caller can drive one rule in isolation.
struct LintEngine {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Public
    func run(_ rules: [any LintDocumentRule], over document: LintDocument) -> [LintOutput] {
        rules.flatMap { rule in
            rule.check(document).map { finding in
                LintOutput(
                    severity: rule.severity,
                    code: rule.code,
                    message: finding.message,
                    target: finding.target ?? .note(document.id),
                    key: finding.key
                )
            }
        }
    }

    // Groups findings by whatever identifies their subject, preserving first
    // appearance — a rule that reports per line still reports once per note.
    func groupBySubject<Item, Subject: Hashable>(
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

    func repeatSuffix(_ lineNumbers: [Int]) -> String {
        guard lineNumbers.count > 1 else { return "" }

        let rest = lineNumbers.dropFirst().map(String.init).joined(separator: ", ")

        return " (+\(lineNumbers.count - 1) more at line\(lineNumbers.count > 2 ? "s" : "") \(rest))"
    }

    // MARK: - Private
}
