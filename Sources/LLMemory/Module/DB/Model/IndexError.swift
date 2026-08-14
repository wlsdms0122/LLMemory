//
//  IndexError.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

enum IndexError: Error, CustomStringConvertible {
    case rebuildAborted([String])

    var description: String {
        switch self {

        case .rebuildAborted(let errors):
            return "rebuild aborted — state would not survive the commit: \(errors.joined(separator: "; "))"
        }
    }
}
