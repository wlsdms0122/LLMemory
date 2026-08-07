//
//  SwiftStringLiterals.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/8/26.
//

import Foundation

// Pulls string literals, with their line numbers, out of Swift source. Architecture guards that look
// at embedded SQL need the literal bodies rather than the code around them.
struct SwiftStringLiterals {
    // MARK: - Property
    private static let tripleQuoted = try! NSRegularExpression(
        pattern: #"\"\"\"(.*?)\"\"\""#,
        options: [.dotMatchesLineSeparators]
    )
    
    let source: String
    
    // MARK: - Initializer
    init(_ source: String) {
        self.source = source
    }
    
    // MARK: - Public
    func bodies() -> [(body: String, line: Int)] {
        multiLine() + singleLine()
    }
    
    // MARK: - Private
    private func multiLine() -> [(body: String, line: Int)] {
        let scanned = source as NSString
        let matches = Self.tripleQuoted.matches(
            in: source,
            range: NSRange(location: 0, length: scanned.length)
        )
        
        return matches.map { match in
            let body = scanned.substring(with: match.range(at: 1))
            let preceding = scanned.substring(to: match.range.location)
            
            return (body, preceding.components(separatedBy: "\n").count)
        }
    }
    
    private func singleLine() -> [(body: String, line: Int)] {
        var literals: [(String, Int)] = []
        
        for (offset, text) in source.components(separatedBy: "\n").enumerated() {
            // A line that opens or closes a multi-line literal is already covered, and its quotes
            // would otherwise pair up wrongly here.
            if text.contains("\"\"\"") { continue }
            
            var rest = Substring(text)
            
            while let open = rest.firstIndex(of: "\"") {
                let after = rest[rest.index(after: open)...]
                
                guard let close = after.firstIndex(of: "\"") else { break }
                
                literals.append((String(after[..<close]), offset + 1))
                
                rest = after[after.index(after: close)...]
            }
        }
        
        return literals
    }
}
