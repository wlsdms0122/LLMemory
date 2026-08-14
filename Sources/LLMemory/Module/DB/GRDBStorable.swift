//
//  GRDBStorable.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB
import Storage

public protocol GRDBStorable: DBStorable where Connection == any DatabaseWriter { }
