# MetalSprocketsMaterialX

MaterialX for Metal, built on function stitching. Intended for SceneSprockets and the MetalSprockets PBR renderer.

Early bootstrap. See `ISSUES.md` for planned work.

## Modules

- `MaterialX`: document model, `.mtlx` parser, and the bundled MaterialX 1.39.4 data libraries (`StandardLibrary`).
- `MaterialXMetal`: `[[stitchable]]` node implementations and `GraphStitcher`, which compiles a nodegraph output into
  one visible function with `MTLFunctionStitchingGraph`.
- `MetalSprocketsMaterialX`: MetalSprockets glue (`StitchedGraph.visibleFunction()`).

## Stitched function

```metal
[[visible]] T graph(float2 texcoord, constant float4 *parameters);
```

Constant inputs live in `parameters`, one `float4` slot each (`StitchedGraph.parameters` / `parameterData`). Change
values without re-stitching.

```swift
let document = try Document(url: url)
let stitcher = try GraphStitcher(nodeLibrary: MetalNodeLibrary(device: device))
var graph = try stitcher.stitch(document.nodeGraph("NG_wood")!, functionName: "material_base_color")
let function = try graph.visibleFunction() // link into a MetalSprockets pipeline
```

Note: stitching drops graph arguments that no node reads. Every graph ends in an `mx_output_*` node that takes all
arguments, so the signature stays fixed.
