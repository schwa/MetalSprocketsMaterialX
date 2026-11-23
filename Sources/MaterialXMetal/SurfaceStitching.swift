import MaterialX
import MaterialXMetalShaders

/// How a surface shader's inputs map onto `MXSurfaceInputs` fields.
///
/// Shaders that are not metallic-roughness (standard_surface, open_pbr_surface) are first run through MaterialX's
/// translation nodegraphs (`bxdf/translation`), as #36-Q1 chose: `translations` lists the translation node
/// categories in order, and `translatedFields` reads the last one's outputs. Their approximations are MaterialX's: coat
/// becomes clearcoat, sheen stays sheen, subsurface and thin film are dropped.
public struct SurfaceMapping: Sendable {
    public struct Field: Sendable {
        /// A shader input name, or a translation output name.
        public var source: String
        /// The `MXSurfaceInputs` field (and `mx_surface_set_<field>` setter).
        public var field: String
    }

    /// Read straight from the shader's inputs.
    public var fields: [Field]
    public var translations: [String]
    /// Read from the last translation node's outputs.
    public var translatedFields: [Field]

    public init(_ fields: [(input: String, field: String)], translations: [String] = [], translatedFields: [(output: String, field: String)] = []) {
        self.fields = fields.map { Field(source: $0.input, field: $0.field) }
        self.translations = translations
        self.translatedFields = translatedFields.map { Field(source: $0.output, field: $0.field) }
    }

    static let gltfTranslatedFields: [(output: String, field: String)] = [
        ("base_color_out", "baseColor"), ("metallic_out", "metallic"), ("roughness_out", "roughness"),
        ("transmission_out", "transmission"), ("sheen_color_out", "sheenColor"), ("sheen_roughness_out", "sheenRoughness"),
        ("clearcoat_out", "clearcoat"), ("clearcoat_roughness_out", "clearcoatRoughness"), ("emissive_out", "emissive"),
    ]

    /// Mappings by surface shader category.
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
        // RealityKit's PBR shader (Apple's nodedefs, StandardLibrary.addingAppleShaderGraphNodes). Its normal is in
        // tangent space like UsdPreviewSurface's and is not mapped yet.
        "realitykit_pbr_surfaceshader": Self([
            ("baseColor", "baseColor"), ("emissiveColor", "emissive"), ("roughness", "roughness"), ("metallic", "metallic"),
            ("ambientOcclusion", "occlusion"), ("specular", "specular"), ("opacity", "opacity"), ("clearcoat", "clearcoat"),
            ("clearcoatRoughness", "clearcoatRoughness"),
        ]),
        "standard_surface": Self(
            [("normal", "normal"), ("coat_normal", "clearcoatNormal"), ("specular_IOR", "ior"), ("specular", "specular"), ("specular_color", "specularColor")],
            translations: ["standard_surface_to_gltf_pbr"],
            translatedFields: gltfTranslatedFields
        ),
        "open_pbr_surface": Self(
            [("geometry_normal", "normal"), ("geometry_coat_normal", "clearcoatNormal"), ("specular_ior", "ior"), ("specular_weight", "specular"), ("specular_color", "specularColor"), ("geometry_opacity", "opacity")],
            translations: ["open_pbr_surface_to_standard_surface", "standard_surface_to_gltf_pbr"],
            translatedFields: gltfTranslatedFields
        ),
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
    func planSurface(_ shader: MaterialXNode, in document: MaterialXDocument, functionName: String, mapping: SurfaceMapping? = nil) throws -> GraphPlan {
        guard let mapping = mapping ?? SurfaceMapping.builtIn[shader.category] else {
            throw MaterialXError.unsupportedNode("surface shader <\(shader.category)> has no MXSurfaceInputs mapping")
        }
        guard let nodeDef = standardLibrary.nodeDef(for: shader) else {
            throw MaterialXError.missingNodeDef(node: "\(shader.name) (\(shader.category))")
        }
        var builder = Builder(stitcher: self)
        builder.documentGraphs = Dictionary(document.nodeGraphs.map { ($0.name, $0) }) { first, _ in first }
        builder.documentColorSpace = document.colorSpace
        builder.documentFilePrefix = document.root["fileprefix"]

        // Translation nodes sit beside the document-level nodes: the first copies the shader's inputs, each later
        // one reads the previous one's `<input>_out` outputs.
        var translationNames: [String] = []
        var extraNodes: [MaterialXElement] = []
        for (index, category) in mapping.translations.enumerated() {
            let name = "\(shader.name)#\(category)"
            guard let translationDef = standardLibrary.nodeDefs.values.first(where: { $0.node == category }) else {
                throw MaterialXError.missingNodeDef(node: category)
            }
            var inputs: [MaterialXElement]
            if index == 0 {
                // Only the inputs the translation declares (geometry inputs are read straight from the shader).
                inputs = shader.element.children(tag: "input").filter { input in
                    input.name.flatMap(translationDef.input)?.type.rawValue == input["type"]
                }
            } else {
                let previous = translationNames[index - 1]
                let previousOutputs = Set((standardLibrary.nodeDefs.values.first { $0.node == mapping.translations[index - 1] }?.outputs ?? []).map(\.name))
                // Inputs the previous translation has no `<input>_out` for keep their defaults.
                inputs = translationDef.inputs.filter { previousOutputs.contains($0.name + "_out") }.map { input in
                    MaterialXElement(tag: "input", attributes: ["name": input.name, "type": input.type.rawValue, "nodename": previous, "output": input.name + "_out"])
                }
            }
            extraNodes.append(MaterialXElement(tag: category, attributes: ["name": name, "type": "multioutput"], children: inputs))
            translationNames.append(name)
        }
        let documentGraph = try Self.documentLevelGraph(document, output: shader.name, type: .surfaceshader, extraNodes: extraNodes)
        let documentScope = Builder.Scope(graph: documentGraph, prefix: "", bindings: [:], colorSpace: document.colorSpace, strings: [:], filePrefix: document.root["fileprefix"])

        var surface = GraphPlan.Operand.surface
        for field in mapping.fields {
            guard let definition = nodeDef.input(field.source) else { continue }
            let value = try builder.resolve(input: shader.input(field.source), definition: definition, owner: shader.name, nodeColorSpace: shader.element["colorspace"] ?? document.colorSpace, in: documentScope)
            surface = try builder.call("mx_surface_set_" + field.field, [surface, value])
        }
        if let translation = translationNames.last {
            for field in mapping.translatedFields {
                let value = try builder.resolve(nodeName: translation, output: field.source, in: documentScope)
                surface = try builder.call("mx_surface_set_" + field.field, [surface, value])
            }
        }
        _ = try builder.call("mx_surface_output", [surface, .context, .parameters, .textures])
        return GraphPlan(functionName: functionName, outputType: .surfaceshader, calls: builder.calls, parameters: builder.parameters, parameterData: builder.parameterData, textures: builder.textures)
    }

    func stitchSurface(_ shader: MaterialXNode, in document: MaterialXDocument, functionName: String, mapping: SurfaceMapping? = nil) throws -> StitchedGraph {
        try stitch(planSurface(shader, in: document, functionName: functionName, mapping: mapping))
    }
}
