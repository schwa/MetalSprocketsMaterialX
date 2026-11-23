import MaterialX
import MaterialXMetalShaders

/// How a surface shader's inputs map onto `MXSurfaceInputs` fields.
public struct SurfaceMapping: Sendable {
    public struct Field: Sendable {
        /// The shader's input name.
        public var input: String
        /// The `MXSurfaceInputs` field (and `mx_surface_set_<field>` setter).
        public var field: String
    }

    public var fields: [Field]

    public init(_ fields: [(input: String, field: String)]) {
        self.fields = fields.map { Field(input: $0.input, field: $0.field) }
    }

    /// Mappings by surface shader category. standard_surface and open_pbr_surface go through their translation
    /// graphs (#36).
    public static let builtIn: [String: Self] = [
        "gltf_pbr": Self([
            ("base_color", "baseColor"), ("metallic", "metallic"), ("roughness", "roughness"), ("normal", "normal"),
            ("occlusion", "occlusion"), ("transmission", "transmission"), ("specular", "specular"),
            ("specular_color", "specularColor"), ("alpha", "opacity"), ("iridescence", "iridescence"),
            ("iridescence_thickness", "iridescenceThickness"), ("sheen_color", "sheenColor"),
            ("sheen_roughness", "sheenRoughness"), ("clearcoat", "clearcoat"), ("clearcoat_roughness", "clearcoatRoughness"),
            ("clearcoat_normal", "clearcoatNormal"), ("emissive", "emissive"),
        ]),
        // UsdPreviewSurface's normal is in tangent space; it is not mapped until normal maps are supported.
        "UsdPreviewSurface": Self([
            ("diffuseColor", "baseColor"), ("emissiveColor", "emissive"), ("specularColor", "specularColor"),
            ("metallic", "metallic"), ("roughness", "roughness"), ("clearcoat", "clearcoat"),
            ("clearcoatRoughness", "clearcoatRoughness"), ("opacity", "opacity"), ("ior", "ior"), ("occlusion", "occlusion"),
        ]),
    ]
}

public extension MXSurfaceInputs {
    /// glTF's defaults, with `normal` and `clearcoatNormal` facing +Z. Surface functions overwrite the fields their
    /// shader maps.
    static var defaults: Self {
        var inputs = Self()
        inputs.baseColor = [1, 1, 1]
        inputs.emissive = .zero
        inputs.specularColor = [1, 1, 1]
        inputs.sheenColor = .zero
        inputs.normal = [0, 0, 1]
        inputs.clearcoatNormal = [0, 0, 1]
        inputs.opacity = 1
        inputs.metallic = 1
        inputs.roughness = 1
        inputs.occlusion = 1
        inputs.specular = 1
        inputs.ior = 1.5
        inputs.iridescenceThickness = 100
        return inputs
    }
}

public extension GraphStitcher {
    /// Compiles every mapped input of surface shader `shader` into one function that fills `MXSurfaceInputs`:
    ///
    ///     void material(thread const MXShadingContext &, constant float4 *parameters, constant MXTexture *textures,
    ///                   thread MXSurfaceInputs *surface)
    ///
    /// Connected inputs (nodegraph outputs or document-level nodes) are stitched; unconnected ones become parameters
    /// named `<shader>.<input>`, so they stay editable. Inputs with a `defaultgeomprop` read the shading context.
    func planSurface(_ shader: Node, in document: Document, functionName: String, mapping: SurfaceMapping? = nil) throws -> GraphPlan {
        guard let mapping = mapping ?? SurfaceMapping.builtIn[shader.category] else {
            throw MaterialXError.unsupportedNode("surface shader <\(shader.category)> has no MXSurfaceInputs mapping")
        }
        guard let nodeDef = standardLibrary.nodeDef(for: shader) else {
            throw MaterialXError.missingNodeDef(node: "\(shader.name) (\(shader.category))")
        }
        var builder = Builder(stitcher: self)
        let documentScope = try Builder.Scope(
            graph: Self.documentLevelGraph(document, output: shader.name, type: .surfaceshader),
            prefix: "",
            bindings: [:],
            colorSpace: document.colorSpace,
            strings: [:],
            filePrefix: document.root["fileprefix"]
        )
        var surface = GraphPlan.Operand.surface
        for field in mapping.fields {
            guard let definition = nodeDef.input(field.input) else { continue }
            let input = shader.input(field.input)
            let value: GraphPlan.Operand
            if let graphName = input?.nodeGraph {
                guard let graph = document.nodeGraph(graphName), let output = input?.output.flatMap(graph.output) ?? graph.outputs.first, let nodeName = output.nodeName else {
                    throw MaterialXError.invalidDocument("\(shader.name).\(field.input) reads a missing nodegraph output")
                }
                let scope = Builder.Scope(graph: graph, prefix: graph.name + "/", bindings: [:], colorSpace: graph.element["colorspace"] ?? document.colorSpace, strings: [:], filePrefix: graph.element["fileprefix"] ?? document.root["fileprefix"])
                value = try builder.resolve(nodeName: nodeName, output: output.output, in: scope)
            } else {
                value = try builder.resolve(input: input, definition: definition, owner: shader.name, nodeColorSpace: shader.element["colorspace"] ?? document.colorSpace, in: documentScope)
            }
            surface = try builder.call("mx_surface_set_" + field.field, [surface, value])
        }
        _ = try builder.call("mx_surface_output", [surface, .context, .parameters, .textures])
        return GraphPlan(functionName: functionName, outputType: .surfaceshader, calls: builder.calls, parameters: builder.parameters, parameterData: builder.parameterData, textures: builder.textures)
    }

    func stitchSurface(_ shader: Node, in document: Document, functionName: String, mapping: SurfaceMapping? = nil) throws -> StitchedGraph {
        try stitch(planSurface(shader, in: document, functionName: functionName, mapping: mapping))
    }
}
