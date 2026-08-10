//
//  Environment.swift
//  LLMemory
//
//  Created by JSilver on 8/7/26.
//

import Foundation

enum Environment {
    static func retrievalSession(cli: String? = nil) -> String? {
        if let cli, !cli.isEmpty {
            return cli
        }
        
        guard let sessionID = ProcessInfo.processInfo.environment["MEMORY_SESSION_ID"], !sessionID.isEmpty else {
            return nil
        }
        
        return sessionID
    }
}
