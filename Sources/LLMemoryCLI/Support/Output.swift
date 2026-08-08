//
//  Output.swift
//  LLMemoryCLI
//
//  Created by JSilver on 8/7/26.
//

import ArgumentParser
import Foundation
import LLMemory

let jsonEncoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.withoutEscapingSlashes]
    
    return encoder
}()

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

func emit<T: Encodable>(_ value: T) {
    do {
        var data = try jsonEncoder.encode(value)
        data.append(0x0A)
        
        FileHandle.standardOutput.write(data)
    } catch {
        FileHandle.standardError.write("emit failed: \(error)\n".data(using: .utf8) ?? Data())
    }
}

func dayString(_ epoch: Int) -> String {
    guard epoch > 0 else { return "-" }
    
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone.current
    
    let components = calendar.dateComponents(
        [.year, .month, .day],
        from: Date(timeIntervalSince1970: TimeInterval(epoch))
    )
    
    return String(
        format: "%04d-%02d-%02d",
        components.year ?? 0,
        components.month ?? 0,
        components.day ?? 0
    )
}

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
