//
//  SwiftSourceFile.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/8/26.
//

import Foundation

// One Swift file, seen the way an architecture guard needs to see it: numbered lines, with the option
// of dropping comments so a rule that forbids a construct is not tripped by prose describing it.
struct SwiftSourceFile {
    // MARK: - Property
    let url: URL
    
    var name: String { url.lastPathComponent }
    
    var text: String { (try? String(contentsOf: url, encoding: .utf8)) ?? "" }
    
    // MARK: - Initializer
    init(_ url: URL) {
        self.url = url
    }
    
    // MARK: - Public
    func lines() -> [(number: Int, text: String)] {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated()
            .map { offset, line in (offset + 1, String(line)) }
    }
    
    func codeLines() -> [(number: Int, text: String)] {
        lines().map { number, text in (number, Self.code(of: text)) }
    }
    
    func location(_ number: Int) -> String { "\(name):\(number)" }
    
    // MARK: - Private
    private static func code(of line: String) -> String {
        guard let comment = line.range(of: "//") else { return line }
        
        return String(line[..<comment.lowerBound])
    }
}
