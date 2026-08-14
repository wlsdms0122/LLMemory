//
//  NoteUnreadable.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import CryptoKit

struct NoteUnreadable: Error, CustomStringConvertible {
    // MARK: - Property
    let path: String
    let reason: String
    
    var description: String { "unreadable note file \(path): \(reason)" }
    
    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}
