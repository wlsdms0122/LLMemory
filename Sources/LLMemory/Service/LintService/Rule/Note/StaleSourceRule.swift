//
//  StaleSourceRule.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation

struct StaleSourceRule: NoteLintRule {
    // MARK: - Property
    let code = "stale-source"
    let severity = LintSeverity.warn
    
    // MARK: - Initializer
    // MARK: - Public
    func check(_ note: NoteLintInput, _ index: LintCorpusIndex) -> [LintFinding] {
        note.doc.source
            .filter { source in
                SourceFingerprint.isDriftCheckable(source)
                    && !FileManager.default.fileExists(
                        atPath: (source as NSString).expandingTildeInPath
                    )
            }
            .map { source in
                .init("source path does not exist: \(source)", key: "source:\(source)")
            }
    }
    
    // MARK: - Private
}
