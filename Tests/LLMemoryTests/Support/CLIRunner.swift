//
//  CLIRunner.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/8/26.
//

import Foundation

struct CLIRunner {
    // MARK: - Property
    // SwiftPM names the built artifact after the executable product, so this literal is the one place
    // the harness can drift out of sync with Package.swift — CLIBinaryWiringTests pins it.
    static let product = "llmemory"
    
    let candidates: [URL]
    
    var binary: URL? {
        candidates.first { url in FileManager.default.fileExists(atPath: url.path) }
    }
    
    // MARK: - Initializer
    init(source: PackageSource = PackageSource()) {
        candidates = ["debug", "release"].map { configuration in
            source.root.appendingPathComponent(".build/\(configuration)/\(Self.product)")
        }
    }
    
    // MARK: - Public
    @discardableResult
    func run(_ arguments: [String], standardInput: String? = nil) -> CLIResult {
        guard let binary else {
            return CLIResult(exitCode: -1, standardOutput: "", standardError: """
                harness: CLI binary not found — the integration suite drives the real executable, so \
                this is a broken harness, not a product failure. Searched:
                \(candidates.map(\.path).joined(separator: "\n"))
                """)
        }
        
        let process = Process()
        
        process.executableURL = binary
        process.arguments = arguments
        process.environment = isolatedEnvironment()
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        if let standardInput {
            let inputPipe = Pipe()
            
            process.standardInput = inputPipe
            
            inputPipe.fileHandleForWriting.write(Data(standardInput.utf8))
            inputPipe.fileHandleForWriting.closeFile()
        }
        
        do {
            try process.run()
        } catch {
            return CLIResult(exitCode: -1, standardOutput: "", standardError: "spawn failed: \(error)")
        }
        
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        
        process.waitUntilExit()
        
        return CLIResult(
            exitCode: process.terminationStatus,
            standardOutput: String(data: outputData, encoding: .utf8) ?? "",
            standardError: String(data: errorData, encoding: .utf8) ?? ""
        )
    }
    
    // MARK: - Private
    // The developer's own shell may point LLMEMORY_*/MEMORY_* at a real brain. Inheriting those would
    // make the suite pass or fail depending on whose machine it runs on.
    private func isolatedEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        
        for key in environment.keys where key.hasPrefix("LLMEMORY_") || key.hasPrefix("MEMORY_") {
            environment.removeValue(forKey: key)
        }
        
        return environment
    }
}
