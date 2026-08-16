//
//  BrainContext.swift
//  LLMemory
//
//  Created by JSilver on 8/10/26.
//

import Foundation

// One brain, as everything about it that is not its database: where its files
// live, what its configuration says, what its genes are set to. They share a
// lifetime and an owner — a Session — and a caller that needs one of them
// usually needs another, so they travel as one value rather than as three
// that could quietly come to describe different brains.
//
// It is passed, not looked up. There was a version of this that answered from
// a task-local with a weak process-wide fallback, which meant a reader that
// forgot to bind got whichever Session had been constructed most recently —
// an answer that was right in every test and unjustifiable in principle. A
// value that arrives in a signature cannot be the wrong brain.
public final class BrainContext: @unchecked Sendable {
    // MARK: - Property
    let paths: Paths
    let config: Config
    let genes: Genes

    var home: URL { paths.brainRoot }

    // MARK: - Initializer
    init(home: String) {
        let config = Config()

        paths = Paths(home: home)
        self.config = config
        genes = Genes(config: config)
    }

    // MARK: - Public
    // MARK: - Private
}
