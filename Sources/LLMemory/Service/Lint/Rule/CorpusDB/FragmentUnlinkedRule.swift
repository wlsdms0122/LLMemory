//
//  FragmentUnlinkedRule.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct FragmentUnlinkedRule: CorpusDBLintRule {
    // MARK: - Property
    let code = "fragment-unlinked"
    let severity = LintSeverity.warn
    
    private let families = NoteFamilyIndex()
    
    // MARK: - Initializer
    // MARK: - Public
    func check(_ db: Database, _ tuning: LintTuning) throws -> [LintFinding] {
        var findings: [LintFinding] = []
        
        for family in try families.families(db, minFamily: tuning.fragmentMinFamily) {
            let unlinked = try families.unlinkedMembers(db, family)
            
            guard !unlinked.isEmpty else { continue }
            
            let sample = unlinked.prefix(3).joined(separator: ", ")
            let more = unlinked.count > 3 ? " +\(unlinked.count - 3) more" : ""
            let name = family.stem ?? family.key
            
            findings.append(
                .init(
                    "`\(name)` family: \(unlinked.count)/\(family.members.count) members "
                        + "hold no deliberate link to a sibling or to "
                        + (family.hasIndex ? "the `\(name)` index" : "an index note")
                        + " — a split without links is knowledge lost, not organized (\(sample)\(more))",
                    target: .note(family.key),
                    key: "unlinked:\(name)"
                )
            )
        }
        
        return findings
    }
    
    // MARK: - Private
}
