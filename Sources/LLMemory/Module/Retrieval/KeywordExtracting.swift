//
//  KeywordExtracting.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation

// Which words in a piece of text carry what it is about. Ranking by frequency
// against a stopword list is one answer; weighting against the corpus, or
// asking an embedding model, are others — and each would still be answering
// this question, which is why the callers name the question and not the answer.
//
// The limit is the caller's: a search box and a term validator want different
// amounts of the same text.
public protocol KeywordExtracting: Sendable {
    func keywords(in text: String, limit: Int) -> [String]
}
