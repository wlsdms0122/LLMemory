//
//  RepeatedFinding.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation

// Collapsing a rule that fires many times into one finding. A rule that
// reports per line would otherwise report a note twenty times over the same
// defect, and twenty findings sharing one identity are twenty findings nobody
// can answer separately.
struct RepeatedFinding {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Public
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
