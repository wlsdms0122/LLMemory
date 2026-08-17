//
//  GistMissingRule.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct GistMissingRule: CorpusDBLintRule {
    // MARK: - Property
    let code = "gist-missing"
    let severity = LintSeverity.warn
    
    private let families = NoteFamilyIndex()
    
    // MARK: - Initializer
    // MARK: - Public
    func check(_ db: Database, _ tuning: LintTuning) throws -> [LintFinding] {
        try families.families(db, minFamily: tuning.fragmentMinFamily).compactMap { family in
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
