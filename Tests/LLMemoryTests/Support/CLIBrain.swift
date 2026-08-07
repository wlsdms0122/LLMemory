//
//  CLIBrain.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/8/26.
//

import Foundation

// A state root built the way a user builds one — `llmemory init` plus `ops apply`, through the real
// binary. Every CLI test gets its own, so no test can depend on what an earlier one left behind.
final class CLIBrain {
    // MARK: - Property
    private let runner = CLIRunner()
    
    let url: URL
    
    var path: String { url.path }
    
    // MARK: - Initializer
    init(prefix: String = "llmemory-cli-test", seeded: Bool = true, bare: Bool = false) throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)")

        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)

        let initialized = runner.run(bare
            ? ["init", "--bare", "--home", url.path]
            : ["init", "--home", url.path])

        guard initialized.succeeded else {
            throw TestFailure("init failed (\(initialized.exitCode)): \(initialized.standardError)")
        }

        if seeded { try seed() }
    }
    
    deinit {
        try? FileManager.default.removeItem(at: url)
    }
    
    // MARK: - Public
    @discardableResult
    func run(_ arguments: [String], standardInput: String? = nil) -> CLIResult {
        runner.run(arguments + ["--home", path], standardInput: standardInput)
    }
    
    @discardableResult
    func applyOps(_ input: String) -> CLIResult {
        run(["ops", "apply", "--input", input, "--json"])
    }
    
    func file(_ relativePath: String) -> URL {
        url.appendingPathComponent(relativePath)
    }
    
    func noteURL(id: String, axis: String) -> URL {
        file("cortex/\(axis)/\(id).md")
    }
    
    // MARK: - Private
    private func apply(_ input: String) throws {
        let result = applyOps(input)
        
        guard result.succeeded else {
            throw TestFailure("""
                seed ops apply failed (\(result.exitCode))
                out: \(result.standardOutput)
                err: \(result.standardError)
                """)
        }
    }
    
    private func seed() throws {
        try apply("""
        {"ops":[
          {"op":"create_note","id":"di-container","axis":"tech","axis_description":"(test axis)","title":"TossDI Container 설계",
           "summary":"의존성 주입 컨테이너","tags":["tech","swift"],
           "entities":["TossDIContainer","PIIMaskingTransformer"],
           "content":"## 구조\\nTossDIContainer 가 PIIMaskingTransformer 를 주입 한다.\\n## 비고\\nresolve 시점 캐싱.\\n"},
          {"op":"create_note","id":"log-masking","axis":"tech","title":"iOS 로그 마스킹 Transformer",
           "summary":"민감정보 마스킹","tags":["tech","ios"],
           "entities":["PIIMaskingTransformer"],
           "content":"## 구조\\nPIIMaskingTransformer 가 로그를 마스킹 한다.\\n"},
          {"op":"create_note","id":"transfer-flow","axis":"flow","axis_description":"(test axis)","title":"이체 플로우",
           "summary":"송금 처리 흐름","tags":["flow","transfer"],
           "content":"## 흐름\\nTransferService 가 이체를 처리한다.\\n"},
          {"op":"create_note","id":"persona-tone","axis":"persona","axis_description":"(test axis)","title":"말투",
           "summary":"어조 규약","tags":["persona","tone"],
           "content":"## 톤\\n간결하고 직설적으로.\\n"},
          {"op":"create_note","id":"old-journal","axis":"journal","axis_description":"(test axis)","title":"오래된 기록",
           "summary":"보관 대상","tags":["journal"],
           "content":"## 기록\\n예전 작업 메모.\\n"}
        ],"rationale":"seed"}
        """)
        try apply("""
        {"ops":[{"op":"set_frontmatter","id":"persona-tone","fields":{"priority":"eager"}}],"rationale":"eager"}
        """)
        try apply("""
        {"ops":[
          {"op":"propose_link","src":"di-container","dst":"log-masking","kind":"assoc","confidence":0.8,"provenance":"test:seed"},
          {"op":"add_retrieval_terms","id":"di-container","kind":"alias","terms":["DI 컨테이너","dependency injection container"],"provenance":"test:seed"},
          {"op":"set_note_meta","id":"di-container","namespace":"capture","key":"source_thread","value":"slack://seed"},
          {"op":"flag","id":"log-masking","kind":"reconsolidate","reason":"near-duplicate suspect"}
        ],"rationale":"enrich"}
        """)
    }
}
