//
//  OutputFormat.swift
//  LLMemoryCLI
//
//  Created by JSilver on 8/15/26.
//

import ArgumentParser
import Foundation
import LLMemory

struct OutputFormat: ParsableArguments {
    // MARK: - Property
    @Flag(name: .long, help: "Emit JSON instead of plain text.")
    var json: Bool = false
    
    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}
