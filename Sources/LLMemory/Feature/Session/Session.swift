//
//  Session.swift
//  LLMemory
//
//  Created by JSilver on 8/7/26.
//

import Foundation

public enum Session {
    public static func configure(home: String) {
        let changed = Paths.configure(home: home)
        
        if changed {
            DB.reset()
            Config.invalidateCache()
        }
        
        Config.warmCache()
    }
    
    public static func retrievalSession(cli: String?) -> String? {
        Env.retrievalSession(cli: cli)
    }
}
