//
//  DayStamp.swift
//  LLMemoryCLI
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import LLMemory

// An epoch second as the day a human reads.
struct DayStamp {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Public
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

    // MARK: - Private
}
