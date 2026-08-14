//
//  PathCollisionRule.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation

struct PathCollisionRule: NoteLintRule {
    // MARK: - Property
    let code = "path-collision"
    let severity = LintSeverity.error
    
    // MARK: - Initializer
    // MARK: - Public
    func check(_ note: NoteLintInput, _ index: LintCorpusIndex) -> [LintFinding] {
        SectionEdit.findPathCollisions(note.body).map { collision in
            .init(
                "section path collision: \(collision.display())",
                key: "path:\(collision.path.display())"
            )
        }
    }
    
    // MARK: - Private
}
