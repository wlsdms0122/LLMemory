//
//  VectorMath.swift
//  LLMemory
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import Accelerate

// Pure numerics behind the algorithmic vectors — PPMI weighting, truncated
// SVD (LAPACK), and cosine similarity. Rows in and out are the vector
// transactions' business.
enum VectorMath {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Public
    static func computePPMI(_ matrix: [Double], n: Int) -> [Double] {
        var rowSum = [Double](repeating: 0, count: n)
        var total = 0.0

        for row in 0..<n {
            var sum = 0.0

            for column in 0..<n { sum += matrix[row * n + column] }

            rowSum[row] = sum
            total += sum
        }

        if total <= 0 { return [Double](repeating: 0, count: n * n) }

        var ppmi = [Double](repeating: 0, count: n * n)

        for row in 0..<n {
            if rowSum[row] <= 0 { continue }

            for column in 0..<n {
                let cell = matrix[row * n + column]

                if cell <= 0 { continue }

                let pointwise = log((cell * total) / (rowSum[row] * rowSum[column]))
                ppmi[row * n + column] = max(0, pointwise)
            }
        }

        return ppmi
    }

    static func truncatedSVD(_ matrix: [Double], n: Int, k: Int) throws -> [Double] {
        var columnMajor = matrix
        var rowCount = __CLPK_integer(n)
        var columnCount = __CLPK_integer(n)
        var lda = __CLPK_integer(n)
        var singularValues = [Double](repeating: 0, count: n)
        var leftVectors = [Double](repeating: 0, count: n * n)
        var ldu = __CLPK_integer(n)
        var rightVectors = [Double](repeating: 0, count: n * n)
        var ldvt = __CLPK_integer(n)
        var jobu = Int8(UInt8(ascii: "A"))
        var jobvt = Int8(UInt8(ascii: "N"))
        var info = __CLPK_integer(0)
        var workQuery = Double(0)
        var lwork = __CLPK_integer(-1)

        dgesvd_(
            &jobu, &jobvt, &rowCount, &columnCount, &columnMajor, &lda,
            &singularValues, &leftVectors, &ldu, &rightVectors, &ldvt,
            &workQuery, &lwork, &info
        )

        lwork = __CLPK_integer(max(1, Int(workQuery)))

        var work = [Double](repeating: 0, count: Int(lwork))

        dgesvd_(
            &jobu, &jobvt, &rowCount, &columnCount, &columnMajor, &lda,
            &singularValues, &leftVectors, &ldu, &rightVectors, &ldvt,
            &work, &lwork, &info
        )

        if info != 0 {
            throw VectorMathError.svdFailed(info: Int(info))
        }

        var projection = [Double](repeating: 0, count: n * k)

        for row in 0..<n {
            for component in 0..<k {
                projection[row * k + component] = leftVectors[component * n + row]
                    * singularValues[component]
            }
        }

        return projection
    }

    static func cosine(_ lhs: [Float], _ rhs: [Float]) -> Double {
        guard lhs.count == rhs.count, !lhs.isEmpty else { return 0 }

        var dot = 0.0
        var lhsNorm = 0.0
        var rhsNorm = 0.0

        for index in 0..<lhs.count {
            dot += Double(lhs[index]) * Double(rhs[index])
            lhsNorm += Double(lhs[index]) * Double(lhs[index])
            rhsNorm += Double(rhs[index]) * Double(rhs[index])
        }

        if lhsNorm == 0 || rhsNorm == 0 { return 0 }

        return dot / (lhsNorm.squareRoot() * rhsNorm.squareRoot())
    }

    // MARK: - Private
}
