//
//  CommandOutput.swift
//  LLMemoryCLI
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import LLMemory

// The plain half of every command's output. `render` takes the blocks the
// command builds; `renderReflected` builds them from the value's own encoded
// shape, for results whose fields are the whole story.
struct CommandOutput {
    // MARK: - Property
    private let output = PlainOutput()

    // MARK: - Initializer
    // MARK: - Public
    func render<T: Encodable>(_ value: T, json: Bool, plain: (T) -> [PlainBlock]) {
        if json {
            JSONOutput().emit(value)
        
            return
        }
    
        output.render(plain(value))
    }

    func renderReflected<T: Encodable>(_ value: T, json: Bool) {
        render(value, json: json) { value in [.keyValue(reflectedPairs(value))] }
    }

    private func reflectedPairs<T: Encodable>(_ value: T) -> [(String, String)] {
        guard let data = try? JSONEncoder.plain.encode(value),
            let dictionary = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return []
        }
    
        return dictionary.keys.sorted().map { key in (key, DisplayString().displayString(dictionary[key] as Any)) }
    }

    // MARK: - Private
}
