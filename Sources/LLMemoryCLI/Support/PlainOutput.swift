//
//  PlainOutput.swift
//  LLMemoryCLI
//
//  Created by JSilver on 8/15/26.
//

import Foundation

struct PlainOutput {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Public
    func render(_ blocks: [PlainBlock]) {
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
    
    func table(_ rows: [[String]], headers: [String]? = nil) {
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
    
    func keyValue(_ pairs: [(String, String)]) {
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
    
    private func oneLine(_ text: String) -> String {
        guard text.contains(where: Self.breaksGrid) else { return text }
        
        return String(text.map { character in Self.breaksGrid(character) ? " " : character })
    }
}
