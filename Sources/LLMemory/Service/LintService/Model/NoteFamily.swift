//
//  NoteFamily.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation

// A fragment family: the notes a split produced, plus the gist that indexes
// them when one exists. `key` is what a finding is reported against — the
// gist if there is one, otherwise the first member — so one family is one
// finding no matter how many members it has.
struct NoteFamily {
    // MARK: - Property
    let stem: String?
    let members: [String]
    let hasIndex: Bool
    let key: String

    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}
