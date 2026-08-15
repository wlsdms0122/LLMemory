//
//  EntityHinting.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation

// Which spans of a text name something the corpus might already hold — a
// ticket code, a product, a person. They are hints, not decisions: whoever
// receives them still has to find the entity. Matching patterns is one way of
// producing them, a recognizer trained on the language is another.
public protocol EntityHinting: Sendable {
    func hints(in text: String) -> [String]
}
