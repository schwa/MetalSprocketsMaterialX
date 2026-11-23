import ArgumentParser
import Foundation
import MaterialX
import MaterialXMetal
import Metal

@main
struct MTLXCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mtlx",
        abstract: "Inspect, validate and stitch MaterialX documents.",
        subcommands: [List.self, Validate.self, Stitch.self, Coverage.self]
    )
}

struct DocumentOptions: ParsableArguments {
    @Argument(help: "A .mtlx file.", completion: .file(extensions: ["mtlx"]))
    var path: String

    func load() throws -> MaterialXDocument {
        try MaterialXDocument(url: URL(fileURLWithPath: path))
    }
}

func makeStitcher(for document: MaterialXDocument? = nil) throws -> GraphStitcher {
    guard let device = MTLCreateSystemDefaultDevice() else {
        throw ValidationError("No Metal device")
    }
    let library = document.map { StandardLibrary.shared.merging([$0]) } ?? .shared
    return GraphStitcher(nodeLibrary: try MetalNodeLibrary(device: device), standardLibrary: library)
}

extension MTLXCommand {
    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "List materials, shaders and nodegraphs.")

        @OptionGroup var document: DocumentOptions

        func run() throws {
            let document = try document.load()
            for material in document.materials {
                print("material \(material.name)")
            }
            for node in document.nodes where node.type != .material {
                let connected = node.inputs.filter { $0.nodeName != nil || $0.nodeGraph != nil }.map(\.name)
                print("\(node.type) \(node.name) <\(node.category)>" + (connected.isEmpty ? "" : " connected: \(connected.joined(separator: ", "))"))
            }
            for graph in document.nodeGraphs {
                print("nodegraph \(graph.name): \(graph.nodes.count) nodes, outputs: \(graph.outputs.map(\.name).joined(separator: ", "))")
            }
        }
    }

    struct Validate: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Report broken references and type mismatches.")

        @OptionGroup var document: DocumentOptions

        func run() throws {
            let issues = try document.load().validate()
            for issue in issues {
                print(issue)
            }
            if !issues.isEmpty {
                throw ExitCode.failure
            }
        }
    }

    struct Stitch: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Stitch nodegraph outputs and connected shader inputs; print each graph and its parameters, or why it cannot be stitched."
        )

        @OptionGroup var document: DocumentOptions

        @Flag(help: "Print the stitching graph of each function.")
        var graph = false

        func run() throws {
            let document = try document.load()
            let stitcher = try makeStitcher(for: document)
            var failures = 0
            func report(_ label: String, _ stitch: () throws -> StitchedGraph) {
                do {
                    let stitched = try stitch()
                    print("✓ \(label): \(stitched.outputType), \(stitched.parameters.count) parameters")
                    for parameter in stitched.parameters {
                        let slots = stitched.parameterData[parameter.slot..<(parameter.slot + parameter.slotCount)]
                        let value = slots.map { slot in (0..<4).map { "\(slot[$0])" }.joined(separator: ", ") }.joined(separator: " | ")
                        print("    [\(parameter.slot)] \(parameter.name): \(parameter.type) = \(value)")
                    }
                    if graph {
                        print(stitched.graphDescription.split(separator: "\n").map { "    " + $0 }.joined(separator: "\n"))
                    }
                } catch {
                    failures += 1
                    print("✗ \(label): \(error)")
                }
            }
            for nodeGraph in document.nodeGraphs {
                for output in nodeGraph.outputs {
                    report("\(nodeGraph.name).\(output.name)") {
                        try stitcher.stitch(nodeGraph, output: output.name, functionName: "mtlx_graph", documentColorSpace: document.colorSpace)
                    }
                }
            }
            for shader in document.nodes where shader.type == .surfaceshader {
                for input in shader.inputs where input.nodeName != nil || input.nodeGraph != nil {
                    report("\(shader.name).\(input.name)") {
                        try stitcher.stitch(input, in: document, functionName: "mtlx_input")
                    }
                }
            }
            if failures > 0 {
                throw ExitCode.failure
            }
        }
    }

    struct Coverage: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Show how the bundled nodedefs are implemented.")

        @Flag(help: "List unsupported nodedefs.")
        var unsupported = false

        func run() throws {
            let coverage = try makeStitcher().coverage()
            for implementation in NodeImplementation.allCases {
                print("\(implementation.rawValue): \(coverage.values.filter { $0 == implementation }.count)")
            }
            if unsupported {
                for name in coverage.filter({ $0.value == .unsupported }).keys.sorted() {
                    print("  \(name)")
                }
            }
        }
    }
}
