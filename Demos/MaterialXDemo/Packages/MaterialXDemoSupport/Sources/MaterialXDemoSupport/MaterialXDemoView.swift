import Metal
import MetalSprockets
import MetalSprocketsMaterialX
import MetalSprocketsUI
import simd
import SwiftUI

/// A grid of the document's color outputs, each drawn on a quad with MaterialXUnlitSurface, with the stitch report
/// (parameters, or why an output failed) underneath.
public struct MaterialXDemoView: View {
    @State private var model: MaterialXDemoModel?
    @State private var isImporting = false

    public init() {}

    public var body: some View {
        Group {
            if let model {
                content(model)
            } else {
                ProgressView()
            }
        }
        .task {
            if model == nil, let device = MTLCreateSystemDefaultDevice() {
                model = try? MaterialXDemoModel(device: device)
            }
        }
    }

    private func content(_ model: MaterialXDemoModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(model.url.lastPathComponent).font(.headline)
                    Spacer()
                    Button("Open…") { isImporting = true }
                }
                if let error = model.loadError {
                    Text(error).foregroundStyle(.red).font(.caption.monospaced())
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 16)], spacing: 16) {
                    ForEach(model.outputs) { output in
                        OutputCell(output: output)
                    }
                }
            }
            .padding()
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.item]) { result in
            if case let .success(url) = result {
                model.open(url)
            }
        }
    }
}

private struct OutputCell: View {
    var output: MaterialXDemoModel.Output

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(output.name).font(.subheadline.monospaced())
            switch output.result {
            case let .success(graph):
                QuadView(graph: graph)
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(.rect(cornerRadius: 6))
                Text(graph.parameters.map { "\($0.name): \($0.type)" }.joined(separator: "\n"))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            case let .failure(error):
                Text("\(error)").font(.caption.monospaced()).foregroundStyle(.red)
            }
        }
    }
}

private struct QuadView: View {
    var graph: StitchedGraph

    static let quad: [Float] = [
        -1, -1, 0, 0, 0, 1, 0, 0,
        1, -1, 0, 0, 0, 1, 1, 0,
        -1, 1, 0, 0, 0, 1, 0, 1,
        1, 1, 0, 0, 0, 1, 1, 1,
    ]

    static func uniforms(time: Float, frame: UInt32) -> MXUnlitUniforms {
        MXUnlitUniforms(time: time, frame: Float(frame))
    }

    var body: some View {
        RenderView { context, _ in
            let buffer = try graph.library.device.makeBuffer(bytes: Self.quad, length: MemoryLayout<Float>.stride * Self.quad.count).orThrow()
            let uniforms = Self.uniforms(time: context.frameUniforms.time, frame: context.frameUniforms.index)
            try RenderPass {
                try MaterialXUnlitSurface(graph: graph, uniforms: uniforms) {
                    Draw { $0.drawPrimitives(primitiveType: .triangleStrip, vertexStart: 0, vertexCount: 4) }
                        .vertexBuffer(buffer, index: 0)
                }
            }
        }
    }
}

private extension Optional {
    func orThrow() throws -> Wrapped {
        guard let self else { throw CocoaError(.featureUnsupported) }
        return self
    }
}
