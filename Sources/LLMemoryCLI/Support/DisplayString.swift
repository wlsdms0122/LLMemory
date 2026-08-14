//
//  DisplayString.swift
//  LLMemoryCLI
//
//  Created by JSilver on 8/15/26.
//

import Foundation

// A loosely-typed value as a table cell. The JSON world hands back `Any`, and
// a table has to print something for every one of them — including the
// distinction between a bool and the number it is bridged as.
struct DisplayString {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Public
    func displayString(_ value: Any?) -> String {
        switch value {
        case nil:
            return "None"
        
        case is NSNull:
            return "None"
        
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return number.boolValue ? "True" : "False"
            }
            
            return number.stringValue
        
        case let bool as Bool:
            return bool ? "True" : "False"
        
        case let string as String:
            return string
        
        case let int as Int:
            return String(int)
        
        case let double as Double:
            return String(double)
        
        case let array as [Any?]:
            return "[" + array.map { element in displayString(element) }.joined(separator: ", ") + "]"
        
        case let array as [Any]:
            return "[" + array.map { element in displayString(element) }.joined(separator: ", ") + "]"
        
        case let dictionary as [String: Any]:
            return "{" + dictionary.keys.sorted()
                .map { key in "\(key): \(displayString(dictionary[key]))" }
                .joined(separator: ", ") + "}"
        
        default:
            return String(describing: value ?? "")
        }
    }
    
    // MARK: - Private
}
