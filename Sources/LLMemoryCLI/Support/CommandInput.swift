//
//  CommandInput.swift
//  LLMemoryCLI
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import LLMemory

// Where a command's payload comes from — the argument if it was given, stdin
// otherwise, refusing an interactive terminal because a prompt that silently
// waits for a human is worse than an error.
struct CommandInput {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Public
    // The one input-acquisition gate — raw argument first, stdin otherwise, with
    // the tty/empty refusals. Both JSON readers build on it.
    func readInputText(_ raw: String?) -> String? {
        let text: String
        
        if let raw, !raw.isEmpty {
            text = raw
        } else {
            if isatty(fileno(stdin)) != 0 {
                FileHandle.standardError.write(
                    "no input; pass --json '<JSON>' or pipe JSON to stdin\n".data(using: .utf8)!
                )
                
                return nil
            }
            
            let data = FileHandle.standardInput.readDataToEndOfFile()
            text = String(data: data, encoding: .utf8) ?? ""
        }
        
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if trimmed.isEmpty {
            FileHandle.standardError.write(
                "empty input; pass --json '<JSON>' or pipe JSON to stdin\n".data(using: .utf8)!
            )
            
            return nil
        }
        
        return trimmed
    }
    
    func readJSON(_ raw: String?) throws -> [String: Any]? {
        guard let trimmed = readInputText(raw) else { return nil }
        
        return parseJSONObject(trimmed)
    }
    
    // Shape validation only — acquisition stays in readInputText.
    private func parseJSONObject(_ trimmed: String) -> [String: Any]? {
        guard let data = trimmed.data(using: .utf8) else {
            FileHandle.standardError.write("invalid encoding\n".data(using: .utf8)!)
            
            return nil
        }
        
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            let detail = (error as NSError).userInfo[NSDebugDescriptionErrorKey] as? String
                ?? error.localizedDescription
            
            FileHandle.standardError.write("invalid JSON: \(detail)\n".data(using: .utf8)!)
            
            return nil
        }
        
        guard let dictionary = object as? [String: Any] else {
            FileHandle.standardError.write("JSON must be an object\n".data(using: .utf8)!)
            
            return nil
        }
        
        return dictionary
    }
    
    // Same gate as readJSON, but hands back the raw text — the ops payload crosses
    // the transaction boundary as a JSON string, so the CLI validates shape here
    // (exit 2 contract) and passes the original bytes through untouched.
    func readJSONText(_ raw: String?) throws -> String? {
        guard let trimmed = readInputText(raw) else { return nil }
        
        guard parseJSONObject(trimmed) != nil else { return nil }
        
        return trimmed
    }
    
    // MARK: - Private
}
