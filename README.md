# MetalSprocketsMaterialX

MaterialX for Metal. Node graphs from `.mtlx` documents are compiled into Metal visible functions with function
stitching (`MTLFunctionStitchingGraph`), for use with MetalSprockets and, later, SceneSprockets' PBR renderer.

Work in progress. Pattern graphs (math, channel, conditional, adjustment, compositing, color management) work.
Images, geometry nodes other than `texcoord`, procedural noise and surface shaders do not yet. See `ISSUES.md`.

## Modules

| Module | Contents |
|---|---|
| `MaterialX` | Document model and parser, `xi:include`, validation, filename/token resolution, and the bundled MaterialX 1.39.4 data libraries (`StandardLibrary`). No Metal. |
| `MaterialXMetalShaders` | The `[[stitchable]]` node library (`StandardLibrary.metal`), compiled by MetalCompilerPlugin. |
| `MaterialXMetal` | `GraphStitcher`, which compiles a nodegraph output into one function, and `MetalNodeLibrary`. |
| `MetalSprocketsMaterialX` | MetalSprockets glue: `StitchedGraph.visibleFunction()`. Re-exports the modules above. |

## Usage

```swift
import MetalSprocketsMaterialX

let document = try MaterialXDocument(url: url)     // follows xi:include
for issue in document.validate() { print(issue) }  // dangling references, type mismatches, unknown nodes

let stitcher = try GraphStitcher(
    nodeLibrary: MetalNodeLibrary(device: device),
    standardLibrary: StandardLibrary.shared.merging([document]) // the document's own nodedefs
)

// A nodegraph output…
var graph = try stitcher.stitch(document.nodeGraph("NG_wood")!, output: "base_color", functionName: "wood_base_color")
// …or whatever a shader input is connected to.
let shader = document.nodes.first { $0.type == .surfaceshader }!
let roughness = try stitcher.stitch(shader.input("specular_roughness")!, in: document, functionName: "wood_roughness")

// Change constants without re-stitching.
if let tint = graph.parameter("tint") {
    graph.parameterData[tint.slot] = [1, 0.5, 0.25, 0]
}

let function = try graph.visibleFunction() // a MetalSprockets VisibleFunction
```

### The stitched function

```metal
#include "MXShadingContext.h" // from MaterialXMetalShaders
[[visible]] T graph(thread const MXShadingContext &context, constant float4 *parameters, constant MXTexture *textures);
```

- `textures` is an argument buffer of `MXTexture` (texture + sampler) slots. Build one with
  `StitchedGraph.makeTextureTable(_:device:)`; the encoder must make the textures resident.

- `context` is the surface point: world and object position, normal, tangent and bitangent, view direction, two UV
  sets, vertex color, time and frame. The caller (a fragment shader) fills it in; geometric nodes read it.
  `StitchedGraph.evaluate(contexts:)` runs a graph for given contexts; `evaluate(at:)` builds them from UVs.

- `T` is the Metal type of the output (`float`, `float2`, `float3` for vector3/color3, `float4`, `int`, `bool`).
- `parameters` holds every constant input, one `float4` slot each (matrices take one slot per column). Bind
  `StitchedGraph.parameterData`; `StitchedGraph.parameters` maps names (`node.input`, or the graph's interface input
  name) to slots.
- Call it directly by linking `graph.function` as a private linked function, or through a visible function table
  when linked as a binary function. A binary function cannot satisfy a direct call.

### How stitching works

- Each node calls the `[[stitchable]]` function named after its nodedef: `ND_add_color3` → `mx_add_color3`.
  Multi-output nodes have one function per output (`mx_separate3_color3_outr`).
- Nodes without a Metal function are expanded from their functional nodegraph (`stdlib_ng.mtlx`, `cmlib_ng.mtlx`, or
  the document's own), recursively.
- Constant inputs become parameter reads. Colors tagged with a `colorspace` are converted to `lin_rec709` with the
  cmlib graphs. Values with a `unit` are converted to `GraphStitcher.targetUnits`.
- Graphs with the same wiring share one stitched library (`MetalNodeLibrary.stitchCount` counts builds).
- Stitching drops graph arguments that no node reads, which would change the signature. Every graph ends in an
  `mx_output_*` node that takes all arguments.

`GraphStitcher.coverage()` reports how each nodedef is implemented. `Tests/MaterialXMetalTests/Resources/node-coverage.txt`
is the checked-in baseline.

## Dependencies and SceneSprockets

This package depends on MetalSprockets and MetalCompilerPlugin only. It must never depend on SceneSprockets:
SceneSprockets depends on this package, and the bridge from `MXSurfaceInputs` to the PBR renderer
(`PBRMaterialUniforms`, the fragment shader hook) lives in SceneSprockets' `SceneSprocketsMaterialX` target.

## Development

```sh
xcb test                                  # macOS
MX_UPDATE_COVERAGE=1 xcb test             # regenerate the node coverage baseline
MX_STITCHING_TIMINGS=1 xcb test -c Release # stitch / link / GPU timings
Scripts/update-materialx-libraries.sh v1.39.4
```

Tests compare node implementations with MaterialX's reference expressions and load MaterialX's example materials.

## License

MIT (`LICENSE`). Bundled MaterialX files are Apache-2.0; see `NOTICE.md`.
