//
//  String+DisplayWidth.swift
//  LLMemoryCLI
//
//  Created by JSilver on 8/15/26.
//

import Foundation

// How many terminal columns a string occupies. A table aligns by this, not by
// character count — CJK and emoji are two columns wide, combining marks and
// zero-width joiners are none.
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
