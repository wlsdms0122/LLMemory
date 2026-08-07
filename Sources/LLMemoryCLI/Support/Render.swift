//
//  Render.swift
//  LLMemoryCLI
//
//  Created by JSilver on 8/7/26.
//

import Foundation

enum PlainBlock {
    case section(String)
    case table([[String]], headers: [String]? = nil)
    case keyValue([(String, String)])
    case text(String)
    case blank
}

enum Plain {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Public
    static func render(_ blocks: [PlainBlock]) {
        for (index, block) in blocks.enumerated() {
            switch block {
            case .section(let title):
                if index > 0 { print("") }
                
                print(title)
            
            case .table(let rows, let headers):
                table(rows, headers: headers)
            
            case .keyValue(let pairs):
                keyValue(pairs)
            
            case .text(let text):
                print(text)
            
            case .blank:
                print("")
            }
        }
    }
    
    static func table(_ rows: [[String]], headers: [String]? = nil) {
        if rows.isEmpty {
            print("(none)")
            
            return
        }
        
        let headers = headers.flatMap { header in header.isEmpty ? nil : header }
        let allRows = (headers.map { header in [header] + rows } ?? rows)
            .map { row in row.map(oneLine) }
        let cellWidths = allRows.map { row in row.map(\.displayWidth) }
        let widths = (0..<(allRows.first?.count ?? 0)).map { column -> Int in
            cellWidths.map { row in row.indices.contains(column) ? row[column] : 0 }.max() ?? 0
        }
        
        for (rowIndex, row) in allRows.enumerated() {
            let pieces = row.enumerated().map { column, cell -> String in
                column == row.count - 1
                    ? cell
                    : cell + String(
                        repeating: " ",
                        count: max(0, widths[column] - cellWidths[rowIndex][column])
                    )
            }
            
            print(pieces.joined(separator: "  "))
            
            if headers != nil && rowIndex == 0 {
                print(
                    String(
                        repeating: "─",
                        count: widths.reduce(0, +) + 2 * (widths.count - 1)
                    )
                )
            }
        }
    }
    
    static func keyValue(_ pairs: [(String, String)]) {
        if pairs.isEmpty {
            print("(none)")
            
            return
        }
        
        let pairs = pairs.map { pair in (oneLine(pair.0), oneLine(pair.1)) }
        let width = pairs.map { pair in pair.0.displayWidth }.max() ?? 0
        
        for (key, value) in pairs {
            let padding = String(repeating: " ", count: max(0, width - key.displayWidth))
            
            print("\(key)\(padding)  \(value)")
        }
    }
    
    // MARK: - Private
    private static func breaksGrid(_ character: Character) -> Bool {
        character.isNewline
            || character.unicodeScalars.contains { scalar in
                scalar.properties.generalCategory == .control
            }
    }
    
    private static func oneLine(_ text: String) -> String {
        guard text.contains(where: breaksGrid) else { return text }
        
        return String(text.map { character in breaksGrid(character) ? " " : character })
    }
}

func render<T: Encodable>(_ value: T, json: Bool, plain: (T) -> [PlainBlock]) {
    if json {
        emit(value)
        
        return
    }
    
    Plain.render(plain(value))
}

func renderReflected<T: Encodable>(_ value: T, json: Bool) {
    render(value, json: json) { value in [.keyValue(reflectedPairs(value))] }
}

private func reflectedPairs<T: Encodable>(_ value: T) -> [(String, String)] {
    guard let data = try? jsonEncoder.encode(value),
        let dictionary = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
        return []
    }
    
    return dictionary.keys.sorted().map { key in (key, displayString(dictionary[key] as Any)) }
}

extension String {
    var displayWidth: Int {
        var width = 0
        
        for cluster in self {
            var clusterWidth = 0
            var emojiPresentation = false
            
            for scalar in cluster.unicodeScalars {
                if scalar.value == 0xFE0F { emojiPresentation = true }
                if scalar.isZeroWidth { continue }
                
                clusterWidth = max(clusterWidth, scalar.isWide ? 2 : 1)
            }
            
            if emojiPresentation && clusterWidth > 0 { clusterWidth = 2 }
            
            width += clusterWidth
        }
        
        return width
    }
}

extension Unicode.Scalar {
    fileprivate var isZeroWidth: Bool {
        switch value {
        case 0x200B...0x200F, 0x2060, 0xFE00...0xFE0F, 0xE0100...0xE01EF:
            return true
        
        case 0x1160...0x11FF, 0xD7B0...0xD7FF:
            return true
        
        default:
            switch properties.generalCategory {
            case .nonspacingMark, .enclosingMark, .format:
                return true
            
            default:
                return false
            }
        }
    }
    
    fileprivate var isWide: Bool {
        switch value {
        case 0x1100...0x115F,
            0x231A...0x231B, 0x2329...0x232A, 0x23E9...0x23EC, 0x23F0, 0x23F3,
            0x25FD...0x25FE, 0x2614...0x2615, 0x2648...0x2653, 0x267F, 0x2693,
            0x26A1, 0x26AA...0x26AB, 0x26BD...0x26BE, 0x26C4...0x26C5, 0x26CE,
            0x26D4, 0x26EA, 0x26F2...0x26F3, 0x26F5, 0x26FA, 0x26FD, 0x2705,
            0x270A...0x270B, 0x2728, 0x274C, 0x274E, 0x2753...0x2755, 0x2757,
            0x2795...0x2797, 0x27B0, 0x27BF, 0x2B1B...0x2B1C, 0x2B50, 0x2B55,
            0x2E80...0x303E,
            0x3041...0x33FF,
            0x3400...0x4DBF, 0x4E00...0x9FFF,
            0xA000...0xA4CF,
            0xA960...0xA97F,
            0xAC00...0xD7A3,
            0xF900...0xFAFF,
            0xFE10...0xFE19, 0xFE30...0xFE52, 0xFE54...0xFE66, 0xFE68...0xFE6B,
            0xFF00...0xFF60,
            0xFFE0...0xFFE6,
            0x16FE0...0x16FE4, 0x17000...0x187F7, 0x18800...0x18CD5,
            0x1B000...0x1B2FB,
            0x1F004, 0x1F0CF, 0x1F18E, 0x1F191...0x1F19A,
            0x1F1E6...0x1F1FF,
            0x1F200...0x1F2FF,
            0x1F300...0x1F9FF,
            0x1FA00...0x1FAFF,
            0x20000...0x3FFFD:
            return true
        
        default:
            return false
        }
    }
}
