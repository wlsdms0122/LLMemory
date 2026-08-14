//
//  IntegrityLevel+Argument.swift
//  LLMemoryCLI
//
//  Created by JSilver on 8/15/26.
//

import ArgumentParser
import Foundation
import LLMemory

// The integrity levels as a command-line argument. It lives here rather than
// beside one command because more than one asks for a level.
extension Indexer.IntegrityLevel: ExpressibleByArgument {
    public var defaultValueDescription: String { String(rawValue) }
    
    public init?(argument: String) {
        guard let raw = Int(argument), let level = Indexer.IntegrityLevel(rawValue: raw) else {
            return nil
        }
        
        self = level
    }
}
