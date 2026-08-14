//
//  JSONOutput.swift
//  LLMemoryCLI
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import LLMemory

// The JSON half of every command's output — one line, slashes unescaped.
struct JSONOutput {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Public
    func emit<T: Encodable>(_ value: T) {
        do {
            var data = try JSONEncoder.plain.encode(value)
            data.append(0x0A)
            
            FileHandle.standardOutput.write(data)
        } catch {
            FileHandle.standardError.write("emit failed: \(error)\n".data(using: .utf8) ?? Data())
        }
    }
    
    // MARK: - Private
}
