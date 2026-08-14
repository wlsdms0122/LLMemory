//
//  QueryTemplate.swift
//  LLMemoryCLI
//
//  Created by JSilver on 8/15/26.
//

import ArgumentParser
import Foundation
import LLMemory

struct QueryTemplate: AsyncParsableCommand {
    struct Output: Encodable {
        // MARK: - Property
        let id: String
        let path: String
        let frame: [TemplateFrameNode]
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    // MARK: - Property
    static let configuration = CommandConfiguration(
        commandName: "template",
        abstract: "Parse a template note's heading frame + per-section guidance.",
        discussion: """
            A *document* note (frontmatter `template: <id>`) must keep this heading
            frame; operations apply rejects any mutation that breaks it. This command shows
            the frame the bot fills in — each node carries the guidance prose authored
            under that heading, so the author knows what each section is for.
            
            Every declared heading is required: it must be present, under its parent,
            in order (a section may be empty — content is free). No section outside the
            frame is allowed at a frame level. Headings *deeper* than a frame leaf, and
            all section content, are free. Heading matching is normalized
            (NFC, lowercase, leading numbering/bullets stripped).
            
            EXAMPLES
                llmemory query template tpl-tech-spec --home brain
                llmemory query template tpl-tech-spec --json --home brain
        """
    )
    
    @OptionGroup var global: GlobalHomeOptions
    @OptionGroup var format: OutputFormat
    
    @Argument(help: "Template note id.")
    var id: String
    
    // MARK: - Initializer
    // MARK: - Public
    func run() async throws {
        let brain = Brain(home: global.home)
        
        let (note, frame) = try await brain.query.template(id: id, cliSessionId: global.sessionId)
        let output = Output(id: note.id, path: note.path, frame: frame)
        
        CommandOutput().render(output, json: format.json) { output in
            var blocks: [PlainBlock] = [
                .keyValue([("id", output.id), ("path", output.path)]),
                .blank
            ]
            
            if output.frame.isEmpty {
                blocks.append(.text("(no frame — template body has no headings)"))
                
                return blocks
            }
            
            var lines: [String] = []
            
            func walk(_ nodes: [TemplateFrameNode]) {
                for node in nodes {
                    lines.append(String(repeating: "#", count: node.level) + " " + node.title)
                    
                    if !node.guide.isEmpty {
                        for line in node.guide.split(
                            separator: "\n",
                            omittingEmptySubsequences: false
                        ) {
                            lines.append("    " + line)
                        }
                    }
                    
                    walk(node.children)
                }
            }
            
            walk(output.frame)
            blocks.append(.text(lines.joined(separator: "\n")))
            
            return blocks
        }
    }
    
    // MARK: - Private
}
