//
//  RetrievalCues.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation

// How many cues a free-text input is worth. Both readers of free text — the
// search box and the associative snapshot — ask the same question of the same
// kind of input, so they ask for the same amount; a term validator looks at a
// single term and says its own number.
public enum RetrievalCues {
    // MARK: - Property
    public static let limit = 15

    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}
