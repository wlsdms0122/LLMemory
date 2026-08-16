//
//  TagNearDuplicateRule.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation

struct TagNearDuplicateRule: CorpusDBLintRule {
    // MARK: - Property
    let code = "tag-near-duplicate"
    let severity = LintSeverity.warn
    
    private let distance = EditDistance()
    
    // MARK: - Initializer
    // MARK: - Public
    func check(_ scope: GRDBReadScope, _ tuning: LintTuning) throws -> [LintFinding] {
        let counts = try scope.run(FetchTagUsageTransaction())
        var findings: [LintFinding] = []
        
        for leftIndex in 0..<counts.count {
            let left = counts[leftIndex]
            
            for rightIndex in (leftIndex + 1)..<counts.count {
                let right = counts[rightIndex]
                
                guard max(left.tag.count, right.tag.count) >= 4 else { continue }
                guard distance.withinOne(left.tag, right.tag) else { continue }
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
