//
//  String+Extension.swift
//  LLMemory
//
//  Created by JSilver on 8/7/26.
//

import Foundation

extension String {
    func unicodeScalarPrefix(_ count: Int) -> String {
        let scalars = unicodeScalars.prefix(count)
        var view = String.UnicodeScalarView()
        view.append(contentsOf: scalars)
        
        return String(view)
    }
    
    func unicodeLines() -> [String] {
        var lines: [String] = []
        var current = ""
        var index = startIndex
        
        while index < endIndex {
            let scalar = self[index]
            
            switch scalar {
            case "\n",
                "\r",
                "\r\n",
                "\u{0B}",
                "\u{0C}",
                "\u{1C}",
                "\u{1D}",
                "\u{1E}",
                "\u{85}",
                "\u{2028}",
                "\u{2029}":
                lines.append(current)
                current = ""
            
            default:
                current.append(scalar)
            }
            
            index = self.index(after: index)
        }
        
        if !current.isEmpty {
            lines.append(current)
        }
        
        return lines
    }
    
    func trimmingTrailingNewlines() -> String {
        var string = self
        
        while string.hasSuffix("\n") {
            string.removeLast()
        }
        
        return string
    }
}

func intListLiteral(_ values: [Int]) -> String {
    "[" + values.map(String.init).joined(separator: ", ") + "]"
}
