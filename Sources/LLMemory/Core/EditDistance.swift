//
//  EditDistance.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation

// Whether two strings are one edit apart — the judgement behind "you
// probably meant this one". Callers decide what a near miss is worth.
struct EditDistance {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Public
    func withinOne(_ left: String, _ right: String) -> Bool {
        if left == right { return false }
        
        let leftCharacters = Array(left)
        let rightCharacters = Array(right)
        let leftCount = leftCharacters.count
        let rightCount = rightCharacters.count
        
        if abs(leftCount - rightCount) > 1 { return false }
        
        if leftCount == rightCount {
            var different = 0
            
            for index in 0..<leftCount where leftCharacters[index] != rightCharacters[index] {
                different += 1
                
                if different > 1 { return false }
            }
            
            return different == 1
        }
        
        let (shorter, longer) = leftCount < rightCount
            ? (leftCharacters, rightCharacters)
            : (rightCharacters, leftCharacters)
        var shortIndex = 0
        var longIndex = 0
        var skipped = false
        
        while shortIndex < shorter.count && longIndex < longer.count {
            if shorter[shortIndex] == longer[longIndex] {
                shortIndex += 1
                longIndex += 1
            } else {
                if skipped { return false }
                
                skipped = true
                longIndex += 1
            }
        }
        
        return true
    }
    
    // MARK: - Private
}
