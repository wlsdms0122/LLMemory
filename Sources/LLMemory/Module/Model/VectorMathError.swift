//
//  VectorMathError.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import Accelerate

enum VectorMathError: Error, CustomStringConvertible {
    case svdFailed(info: Int)

    var description: String {
        switch self {
        case .svdFailed(let info):
            return "SVD failed (LAPACK dgesvd info=\(info))"
        }
    }
}
