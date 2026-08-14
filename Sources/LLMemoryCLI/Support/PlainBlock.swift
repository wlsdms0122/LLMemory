//
//  PlainBlock.swift
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
