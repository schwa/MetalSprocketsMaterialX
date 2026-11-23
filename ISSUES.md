# ISSUES.md

File format: <https://github.com/schwa/issues-format>

---

## 1: xi:include elements are not followed

+++
status: closed
priority: high
kind: feature
labels: effort:m, area:document
created: 2026-11-23T12:40:29Z
updated: 2026-11-23T12:57:50Z
closed: 2026-11-23T12:57:50Z
+++

Documents that split definitions across files with <xi:include href=...> load only the top file. Included nodedefs, nodegraphs and materials are missing. Relative hrefs, search paths and include cycles are not handled.

- `2026-11-23T12:57:50Z`: Document(url:) and Document(data:baseURL:) splice xi:include'd documents (relative to the including file, nested, cycles throw). Library search paths are not implemented. Test: xiIncludeIsFollowed.

---

## 2: Nodedef inheritance (inherit attribute) is not resolved

+++
status: closed
priority: high
kind: feature
labels: effort:s, area:document
created: 2026-11-23T12:40:29Z
updated: 2026-11-23T12:57:13Z
closed: 2026-11-23T12:57:13Z
+++

Nodedefs such as ND_standard_surface_surfaceshader declare inherit="ND_standard_surface_surfaceshader_100". The inherited inputs and outputs are not merged, so a node matched to the child nodedef only sees the child's own inputs.

- `2026-11-23T12:57:13Z`: StandardLibrary merges inherited inputs/outputs (own entries override, parent order kept). Test: nodeDefInheritance.

---

## 3: Nodedef versioning is ignored

+++
status: closed
priority: medium
kind: feature
labels: effort:s, area:document
created: 2026-11-23T12:40:29Z
updated: 2026-11-23T13:06:47Z
closed: 2026-11-23T13:06:47Z
+++

MaterialX nodedefs have version and isdefaultversion attributes, and nodes can request a version. StandardLibrary picks a nodedef by category and types only, so a document that asks for an older version of a node gets an arbitrary one.

- `2026-11-23T13:06:47Z`: NodeDef reads version/isdefaultversion, Node reads version. nodeDef(for:) requires an exact version match when the node asks for one and otherwise prefers the default version. Test: nodeDefVersionSelection.

---

## 4: Type defaults and typedefs are not modelled

+++
status: closed
priority: medium
kind: feature
labels: effort:m, area:document
created: 2026-11-23T12:40:29Z
updated: 2026-11-23T13:07:35Z
closed: 2026-11-23T13:07:35Z
+++

ValueType is a string wrapper. Custom <typedef> elements, struct types (1.39), multi-output types and the semantic and context attributes are not read. Integer and boolean inputs parse as floats.

- `2026-11-23T13:07:35Z`: Value has integer and boolean cases (strict parsing; .numbers still bridges them to floats). TypeDef (semantic, context, struct members) read into Document.typeDefs and StandardLibrary.typeDefs. Struct-typed ports are not stitched. Tests: parsesValues, typeDefsAreRead.

---

## 5: Unit and colorspace attributes are not applied

+++
status: closed
priority: medium
kind: feature
labels: effort:l, area:document, area:color
created: 2026-11-23T12:40:29Z
updated: 2026-11-23T13:12:09Z
closed: 2026-11-23T13:12:09Z
+++

colorspace on the document, nodegraph, image and input values, and unit / unittype on distance and angle inputs, are parsed into attributes but have no effect. Values and textures in srgb_texture, acescg, lin_rec709 etc. are used as if already in the working space.

- `2026-11-23T13:12:09Z`: Color3/color4 values set in the document are converted from their colorspace (input > node > nodegraph > document) to lin_rec709 by inlining the cmlib nodegraph; nodedef defaults and functional-graph internals are left alone. Values with unit/unittype convert to GraphStitcher.targetUnits (default meter, degree) using StandardLibrary.units from <unitdef>. Image texture colorspaces wait on image support (#18). Tests: ColorSpaceAndUnitTests.

---

## 6: Tokens and string substitution in filenames are not resolved

+++
status: closed
priority: medium
kind: feature
labels: effort:m, area:document
created: 2026-11-23T12:40:29Z
updated: 2026-11-23T13:08:21Z
closed: 2026-11-23T13:08:21Z
+++

<token> elements and [token] substitution in filename values (e.g. textures/[albedo].png), the fileprefix attribute inherited from ancestors, and UDIM <UDIM> / <UVTILE> patterns are not resolved.

- `2026-11-23T13:08:21Z`: Document.resolvedFilename(_:node:graph:) applies [token] substitution (node tokens override graph/root) and the nearest fileprefix (input > node > graph > root). FilenamePattern expands <UDIM> / <UVTILE> per tile. Interface-driven tokens (token values connected to nodedef inputs) are not handled. Test: filenamesResolveTokensAndPrefixes.

---

## 7: Looks, collections, geominfo and variants are not loaded

+++
status: closed
priority: low
kind: feature
labels: effort:m, area:document
created: 2026-11-23T12:40:29Z
updated: 2026-11-23T13:33:12Z
closed: 2026-11-23T13:33:12Z
+++

<look>, <materialassign>, <collection>, <geominfo>, <propertyset> and <variantset> are skipped by Document. Material assignment by geometry name and variant selection are unavailable.

- `2026-11-23T13:33:12Z`: Document.looks (with inherit), collections (GeometryCollection: includegeom/excludegeom/includecollection, cycles throw), variantSets() and variantassigns, geomInfos/propertySets. materialAssignments(for:look:) returns the assignments that apply to a geometry path, inherited looks first, using MaterialX's GeomPath matching (prefix either way; exclude requires containment; '/' universal). Which of several matching assignments wins is left to the caller. Tests: LookTests.

---

## 8: Documents cannot be written back to .mtlx

+++
status: closed
priority: low
kind: feature
labels: effort:m, area:document
created: 2026-11-23T12:40:29Z
updated: 2026-11-23T13:33:48Z
closed: 2026-11-23T13:33:48Z
+++

Document and Element are read-only. There is no serializer, so tools cannot edit a material and save it.

- `2026-11-23T13:33:48Z`: Element.xmlString(), Document.data() / write(to:) and a public Document(root:) for edited trees. Round-trips the bundled stdlib and system .mtlx files exactly (element tree equality). Limits: attribute order is normalized (name, type, nodedef, then sorted), XML comments are dropped by the parser, and xi:include content is written inline. Tests: WriterTests.

---

## 9: No document validation

+++
status: closed
priority: medium
kind: feature
labels: effort:m, area:document
created: 2026-11-23T12:40:29Z
updated: 2026-11-23T13:09:03Z
closed: 2026-11-23T13:09:03Z
+++

Documents are trusted as given. There is no check for dangling nodename references, type mismatches between connected inputs and outputs, unknown categories, or interfacename pointing at missing inputs, so errors only appear at stitch time or not at all.

- `2026-11-23T13:09:03Z`: Document.validate(library:) returns ValidationIssues for dangling nodename/nodegraph/output/interfacename, unknown node categories, missing multi-output outputs and type mismatches on connections. Tests: validationReportsProblems, validDocumentHasNoIssues.

---

## 10: Swift API surface of the MaterialX module needs a design pass

+++
status: open
priority: medium
kind: task
labels: effort:m, area:document, area:api
created: 2026-11-23T12:40:29Z
updated: 2026-11-23T12:55:47Z
+++

Types are named Element, Node, Input, Output, Value, Document in module MaterialX. They clash easily with other modules imported by SceneSprockets and MetalSprockets (e.g. Node in SceneSprockets). Naming, Sendable, Codable and mutability were picked quickly during bootstrap.

- `2026-11-23T13:19:31Z`: Question 1 (design): Rename the MaterialX module's generic types with a MaterialX prefix (MaterialXDocument, MaterialXNode, MaterialXInput, MaterialXOutput, MaterialXValue, MaterialXElement; NodeDef/NodeGraph/TypeDef keep their names) so they do not clash with SceneSprockets' Node etc.? Recommended: Yes
- `2026-11-23T13:39:37Z`: I'd rather not :-(
- `2026-11-23T13:39:45Z`: Answer 1: I'd rather not :-(

---

## 11: Most stdlib math nodes have no Metal implementation

+++
status: open
priority: high
kind: feature
labels: effort:xl, area:nodes, area:stitching
created: 2026-11-23T12:40:29Z
updated: 2026-11-23T12:55:47Z
+++

StandardLibrary.metal covers add, subtract, multiply, divide, min, max, mix, combine3 and two converts. stdlib_defs.mtlx has ~690 nodedefs. Missing math: modulo, fract, invert, absval, sign, floor, ceil, round, power, safepower, sin/cos/tan/asin/acos/atan2, sqrt, ln, exp, clamp, normalize, magnitude, distance, dotproduct, crossproduct, transformpoint/vector/normal, transformmatrix, normalmap, creatematrix, transpose, determinant, invertmatrix, rotate2d, rotate3d, reflect, refract, place2d, trianglewave, etc.

---

## 12: Channel and conversion nodes are missing

+++
status: closed
priority: high
kind: feature
labels: effort:m, area:nodes
created: 2026-11-23T12:40:29Z
updated: 2026-11-23T12:59:03Z
closed: 2026-11-23T12:59:03Z
+++

extract, separate2/3/4, combine2/4, swizzle (1.38 compat), convert for all type pairs, and the FA/vector variants are mostly absent from StandardLibrary.metal.

- `2026-11-23T12:59:03Z`: Added Metal functions for every extract, combine2/3/4 and convert nodedef (except *_surfaceshader), plus integer/boolean parameter readers. separate2/3/4 are multi-output nodes and wait on #25. swizzle is not in the 1.39 libraries. Tests: ChannelNodeTests.

---

## 13: Logical and conditional nodes are missing

+++
status: closed
priority: medium
kind: feature
labels: effort:m, area:nodes
created: 2026-11-23T12:40:29Z
updated: 2026-11-23T13:09:57Z
closed: 2026-11-23T13:09:57Z
+++

ifgreater, ifgreatereq, ifequal, switch, and/or/not/xor (1.39 boolean nodes) have no implementation. Boolean and integer inputs also have no parameter readers.

- `2026-11-23T13:09:57Z`: Metal functions for ifgreater/ifgreatereq/ifequal (float, I and B variants, boolean outputs), and/or/not; switch and xor stitch through their stdlib nodegraphs. Boolean/integer graph outputs supported. Matrix variants wait on matrix parameter support. Reference-expression test covers the non-boolean if* nodes. Tests: ConditionalNodeTests.

---

## 14: Adjustment and compositing nodes are missing

+++
status: closed
priority: medium
kind: feature
labels: effort:l, area:nodes
created: 2026-11-23T12:40:29Z
updated: 2026-11-23T13:13:56Z
closed: 2026-11-23T13:13:56Z
+++

remap, smoothstep, luminance, rgbtohsv, hsvtorgb, contrast, range, hsvadjust, saturate, colorcorrect, premult, unpremult, plus, minus, difference, burn, dodge, screen, overlay, disjointover, in, mask, matte, out, over, inside, outside have no implementation.

- `2026-11-23T13:13:56Z`: Every non-shader adjustment/compositing nodedef stitches: remap, smoothstep, luminance, rgbtohsv/hsvtorgb, burn, dodge, plus, minus, difference, screen, inside, outside, over, in, mask, matte, out, disjointover, premult, unpremult as Metal functions (ported from genglsl); range, contrast, saturate, hsvadjust, colorcorrect through their nodegraphs. Also added absval, sign, clamp. mix_surfaceshader etc. wait on shader closures (#33). Tests: AdjustmentAndCompositingTests; reference-expression test covers the inline ones.

---

## 15: Procedural pattern nodes are missing

+++
status: open
priority: high
kind: feature
labels: effort:xl, area:nodes
created: 2026-11-23T12:40:29Z
updated: 2026-11-23T12:55:47Z
+++

noise2d, noise3d, fractal2d/3d, cellnoise2d/3d, worleynoise2d/3d, unifiednoise2d/3d, ramplr, ramptb, ramp4, splitlr, splittb, randomfloat, randomcolor, checkerboard, line, circle, cloverleaf, hexagon, grid, crosshatch, tiledcircles, tiledcloverleafs, tiledhexagons, bump have no implementation. MaterialX's genmsl lib (mx_noise.metal etc.) is available on disk for reference.

---

## 16: Geometric nodes other than texcoord are missing

+++
status: open
priority: high
kind: feature
labels: effort:m, area:nodes, area:geometry
depends: 22
created: 2026-11-23T12:40:29Z
updated: 2026-11-23T12:59:10Z
+++

position, normal, tangent, bitangent, geomcolor, geompropvalue, time, frame, viewdirection and the space input (model/object/world) are not available. The stitched function only receives a texture coordinate.

- `2026-11-23T12:59:10Z`: Question 1 (decision): Implement position/normal/tangent/bitangent/geomcolor/time/frame/viewdirection as readers of the MXShadingContext proposed in #22-Q1 once that is answered, with the space input (model/object/world) choosing between the struct's object and world fields? Recommended: Yes
- `2026-11-23T13:40:33Z`: Answer 1: YES

---

## 17: texcoord index input is ignored

+++
status: open
priority: medium
kind: bug
labels: effort:s, area:nodes, area:geometry
depends: 22
created: 2026-11-23T12:40:29Z
updated: 2026-11-23T13:05:26Z
+++

texcoord nodes always read the single texcoord argument; index=1 (second UV set) behaves like index=0.

- `2026-11-23T13:05:26Z`: texcoord with index != 0 now throws unsupportedNode instead of silently reading UV set 0 (test secondUVSetIsRejected). Reading the second set needs the shading context from #22.

---

## 18: Image and texture nodes are not supported

+++
status: open
priority: critical
kind: feature
labels: effort:l, area:nodes, area:textures
depends: 22, 23
created: 2026-11-23T12:40:29Z
updated: 2026-11-23T12:56:14Z
+++

image, tiledimage, triplanarprojection, hextiledimage, gltf_image/gltf_colorimage/gltf_normalmap and their uaddressmode, vaddressmode, filtertype, framerange, frameoffset, frameendaction, default and texcoord inputs have no implementation. Stitched functions have no way to reach textures or samplers today.

- `2026-11-23T12:56:14Z`: Question 1 (decision): Implement image nodes only after #22 (shading context) and #23 (texture passing) are designed, with textures reaching stitched functions through an argument buffer of texture2d+sampler pairs indexed by a parameter slot? Recommended: Yes

---

## 19: Functional nodegraphs (*_ng.mtlx) are not used as node implementations

+++
status: closed
priority: high
kind: feature
labels: effort:l, area:nodes, area:stitching
created: 2026-11-23T12:40:29Z
updated: 2026-11-23T13:01:36Z
closed: 2026-11-23T13:01:36Z
+++

Many nodedefs are implemented in stdlib_ng.mtlx / pbrlib_ng.mtlx as nodegraphs rather than source. StandardLibrary loads them but GraphStitcher does not inline a nodegraph implementation when a node has no Metal function, so those nodes fail with unsupportedNode.

- `2026-11-23T13:01:36Z`: GraphStitcher inlines a nodedef's functional nodegraph when no Metal function exists (nested scopes, interface inputs bound to caller arguments, unbound ones become parameters). StandardLibrary(documents:) / merging(_:) add document-local nodedefs. Multi-output implementation graphs still wait on #25. Test: FunctionalNodeGraphTests.

---

## 20: Node coverage is not tracked

+++
status: closed
priority: medium
kind: task
labels: effort:s, area:nodes, area:testing
created: 2026-11-23T12:40:29Z
updated: 2026-11-23T13:17:07Z
closed: 2026-11-23T13:17:07Z
+++

There is no report of which nodedefs in the bundled libraries have a Metal function, a nodegraph implementation, or neither. Coverage regressions go unnoticed.

- `2026-11-23T13:17:07Z`: GraphStitcher.coverage() classifies every nodedef as metal, nodeGraph (functional graph with all nodes supported) or unsupported. NodeCoverageTests compares against Tests/MaterialXMetalTests/Resources/node-coverage.txt (391 supported: 293 metal, 98 nodeGraph) and fails when a nodedef loses support; regenerate with MX_UPDATE_COVERAGE=1.

---

## 21: Node implementations are not checked against MaterialX reference results

+++
status: closed
priority: high
kind: task
labels: effort:l, area:nodes, area:testing
created: 2026-11-23T12:40:29Z
updated: 2026-11-23T13:05:01Z
closed: 2026-11-23T13:05:01Z
+++

Each Metal node implementation is written by hand. Nothing compares its output against MaterialX's own genmsl/genglsl implementations or reference renders for the same inputs.

- `2026-11-23T13:05:01Z`: ReferenceImplementationTests compiles each inline sourcecode expression from MaterialX's stdlib_genglsl_impl.mtlx (vendored, genmsl reuses these) into a Metal kernel and compares it with the stitched node for fixed inputs; >50 nodedefs covered, all match. Nodes implemented by .glsl files (noise, image, ...) are not covered. Found: Apple's shipped stdlib_genglsl_impl.mtlx (RealityComposerPro USDLib_FormatLoaderProxy) has an unescaped '&&' at IM_logical_and_genglsl and is not well-formed XML; the vendored copy escapes it.

---

## 22: Stitched graph signature only carries texcoord and parameters

+++
status: open
priority: critical
kind: feature
labels: effort:m, area:stitching, area:geometry
created: 2026-11-23T12:40:29Z
updated: 2026-11-23T12:55:47Z
+++

The stitched function is T(float2 texcoord, constant float4 *parameters). There is no way to pass position, normal, tangent, view direction, time, vertex color, or multiple UV sets. Changing it later breaks every caller, so the shading context needs to be designed before more nodes are added.

- `2026-11-23T12:56:14Z`: Question 1 (design): Should the stitched function become T graph(thread const MXShadingContext &context, constant float4 *parameters), with MXShadingContext (world/object position and normal, tangent, bitangent, view direction, texcoord[2], vertex color, time, frame) in a shared header? Recommended: Yes
- `2026-11-23T13:38:12Z`: Related: #61 (evaluation kernels hard-code the current signature).

---

## 23: Textures and samplers cannot be passed through stitched graphs

+++
status: open
priority: critical
kind: feature
labels: effort:l, area:stitching, area:textures
depends: 22
created: 2026-11-23T12:40:29Z
updated: 2026-11-23T12:56:27Z
+++

Image nodes need texture and sampler access. Whether [[stitchable]] functions can take texture2d/sampler arguments or must go through an argument buffer, and how that interacts with residency in MetalSprockets, is not investigated.

- `2026-11-23T12:56:27Z`: Question 1 (design): Pass textures to stitched functions through an argument buffer (array of texture2d+sampler) given as a third graph argument, with image nodes taking a slot index from the parameter buffer? Recommended: Yes

---

## 24: Parameter buffer layout wastes space and has no typed access

+++
status: open
priority: low
kind: enhancement
labels: effort:s, area:stitching
created: 2026-11-23T12:40:29Z
updated: 2026-11-23T12:55:47Z
+++

Every parameter takes one float4 slot, including floats. parameterData is [SIMD4<Float>] indexed by slot number; there is no typed setter by name (e.g. set("tint", to: SIMD3)) and no validation of type on write.

- `2026-11-23T13:30:08Z`: Question 1 (decision): Leave the one-float4-slot-per-parameter layout as is (simple readers, 16 B per scalar; a 50-input material is under 1 KB) and close #24 with the typed setters, instead of packing scalars into shared slots? Recommended: Yes, keep the layout
- `2026-11-23T13:38:12Z`: Related: #59 (layout is spread over four places).

---

## 25: Multi-output nodes and nodegraph outputs are not supported

+++
status: closed
priority: high
kind: feature
labels: effort:l, area:stitching
created: 2026-11-23T12:40:29Z
updated: 2026-11-23T13:02:50Z
closed: 2026-11-23T13:02:50Z
+++

Nodes with several outputs (separate3, artistic_ior, gltf_* nodes) and inputs with output="..." are ignored by GraphStitcher. stitch() also compiles one nodegraph output at a time; a surface shader with many connected inputs needs one function per input or one function with several results.

- `2026-11-23T13:02:50Z`: Multi-output nodes: one Metal function per output (mx_<nodedef>_<output>), output= references resolve per output with shared inputs, type="multioutput" nodedef matching, functional graphs select the requested output, separate2/3/4 implemented. One stitched function still returns one value; filling all shader inputs at once is part of #34. Tests: MultiOutputTests.

---

## 26: Top-level nodes and nodegraph references from shader inputs are not stitched

+++
status: closed
priority: high
kind: feature
labels: effort:m, area:stitching
created: 2026-11-23T12:40:29Z
updated: 2026-11-23T12:59:47Z
closed: 2026-11-23T12:59:47Z
+++

GraphStitcher compiles a NodeGraph only. Shader inputs connected with nodegraph=... output=..., or to nodes declared at document level (outside any nodegraph), cannot be compiled.

- `2026-11-23T12:59:47Z`: GraphStitcher.stitch(_:in:functionName:) stitches a shader input connected to a nodegraph output or a document-level node (top-level nodes wrapped in a synthetic graph). Added constant nodes. Test: ShaderInputStitchingTests.

---

## 27: Stitched libraries are not cached

+++
status: closed
priority: medium
kind: enhancement
labels: effort:s, area:stitching, area:performance
created: 2026-11-23T12:40:29Z
updated: 2026-11-23T13:06:12Z
closed: 2026-11-23T13:06:12Z
+++

Every stitch() call builds a new MTLStitchedLibrary. Two materials with the same graph topology but different constant values produce identical libraries. There is no cache keyed by topology, and no measurement of stitch cost per graph size.

- `2026-11-23T13:06:12Z`: MetalNodeLibrary caches stitched libraries by function name + graph topology (wiring, not constants); stitchCount reports misses. Node function cache is now Mutex-protected. Test: StitchCacheTests. Stitch-cost numbers are #28.

---

## 28: Stitching cost and runtime performance are unmeasured

+++
status: closed
priority: medium
kind: task
labels: effort:m, area:stitching, area:performance
created: 2026-11-23T12:40:29Z
updated: 2026-11-23T13:26:04Z
closed: 2026-11-23T13:26:04Z
+++

No numbers for stitch time, pipeline link time (binary vs static linking), or GPU time of a stitched material compared with hand-written or MaterialX-generated MSL. MetalSprocketsParticles has a stitching timing harness that could be compared with.

\- `2026-11-23T13:26:04Z`: StitchingPerformanceTests (MX_STITCHING_TIMINGS=1) measures stitch time, pipeline link time for direct private linking vs binary function + visible function table (MetalSprockets' .binary linking), and GPU time over 1M threads vs the same math hand-written. Release, M-series, chains of multiply/add:
nodes | stitch ms | link private | link binary+table | GPU private | GPU binary+table | GPU hand-written
10 | 0.37 | 1.92 | 0.25 | 0.054 | 0.030 | 0.021
50 | 0.67 | 0.13 | 0.09 | 0.031 | 0.056 | 0.022
200 | 41.2 | 27.3 | 12.9 | 0.251 | 0.188 | 0.020
Numbers are noisy (Metal's shader cache makes repeated graphs fast). Hand-written wins mostly because its constants are literals the compiler folds, while stitched constants come from the parameter buffer (#30). Findings: binary functions cannot satisfy a direct [[visible]] call ('unresolved visible function reference'), only a visible function table; and stitching recursed once per node, overflowing a secondary thread's stack at ~40 nodes (fixed in this commit, DeepGraphTests).

---

## 29: Stitching errors are hard to diagnose

+++
status: closed
priority: low
kind: enhancement
labels: effort:s, area:stitching
created: 2026-11-23T12:40:29Z
updated: 2026-11-23T13:30:53Z
closed: 2026-11-23T13:30:53Z
+++

When makeLibrary(stitchedDescriptor:) fails, the error names the stitching graph only. There is no way to dump the graph (nodes, argument wiring, types) for debugging.

- `2026-11-23T13:30:53Z`: StitchedGraph.graphDescription dumps the stitching graph (one line per function node: n<i> = function(args) // MaterialX node). When Metal rejects a graph, the error is MaterialXError.stitchingFailed with Metal's message plus the dump. Test: descriptionNamesFunctionsAndNodes.

---

## 30: Constant folding before stitching is not done

+++
status: open
priority: low
kind: enhancement
labels: effort:m, area:stitching, area:performance
created: 2026-11-23T12:40:29Z
updated: 2026-11-23T12:55:47Z
+++

Subgraphs that depend only on constants are stitched as function calls and evaluated per pixel. SceneSprocketsMaterialX already folds math on constants on the CPU (#609 in SceneSprockets).

- `2026-11-23T13:31:01Z`: Question 1 (design): Add an opt-in GraphStitcher.foldConstants that stitches each constant-only subgraph separately, evaluates it once on the GPU with a 1-thread compute dispatch, and replaces it with one parameter slot (so no CPU copy of node semantics is needed), accepting that folded inputs are no longer editable by their original parameter names? Recommended: Yes, opt-in, GPU-evaluated

---

## 31: Node library is compiled by SwiftPM's default .metal processing

+++
status: closed
priority: medium
kind: task
labels: effort:s, area:build, area:shaders
created: 2026-11-23T12:40:29Z
updated: 2026-11-23T13:16:12Z
closed: 2026-11-23T13:16:12Z
+++

StandardLibrary.metal is a .process resource compiled into the target bundle's default.metallib. Other packages in this family use MetalCompilerPlugin with a bundle finder, debug metallibs and shared headers. Whether the default path works under Xcode builds, visionOS and iOS is untested.

- `2026-11-23T13:16:12Z`: Node library moved to a MaterialXMetalShaders target compiled by MetalCompilerPlugin (debug metallibs with source in Debug), with a bundle finder (NSBundle.materialXMetalShadersBundle) and public include/ folder for shared headers, matching the sibling packages. iOS/visionOS builds are #52.

---

## 32: Unused stitching graph arguments change the stitched signature

+++
status: closed
priority: low
kind: documentation
labels: effort:xs, area:stitching
created: 2026-11-23T12:40:29Z
updated: 2026-11-23T13:35:38Z
closed: 2026-11-23T13:35:38Z
+++

Found during bootstrap: MTLFunctionStitchingGraph drops input arguments that no node reads, so a graph that ignores texcoord compiled as T(constant float4 *) and the caller read garbage. The mx_output_* sink nodes work around it. This is not documented in the README, and there is no test for a graph that reads neither argument.

- `2026-11-23T13:35:38Z`: Documented in README (How stitching works) and at mx_output_* in StandardLibrary.metal (#53). Covered by tests: texcoordOnlyGraph (parameters argument unused) and the constant-only graphs, e.g. ShaderInputStitchingTests and ConditionalNodeTests (texcoord unused). A graph reading neither argument cannot be built: every constant becomes a parameter read, so a parameters read is always present unless the graph has no inputs at all, and then the output sink still takes both arguments.

---

## 33: No surface shader evaluation (standard_surface, open_pbr_surface, gltf_pbr, UsdPreviewSurface)

+++
status: open
priority: critical
kind: feature
labels: effort:xl, area:pbr, area:shading
created: 2026-11-23T12:40:29Z
updated: 2026-11-23T12:55:47Z
+++

The library compiles pattern graphs only. Surface shader nodes and their BSDF/EDF/VDF closures (pbrlib: oren_nayar_diffuse_bsdf, dielectric_bsdf, conductor_bsdf, generalized_schlick_bsdf, subsurface_bsdf, sheen_bsdf, thin_film_bsdf, layer, mix, add, multiply, uniform_edf, ...) have no Metal representation.

---

## 34: No mapping from MaterialX surface shaders to MetalSprocketsPBR material inputs

+++
status: open
priority: critical
kind: feature
labels: effort:l, area:pbr, area:integration
depends: 22
created: 2026-11-23T12:40:29Z
updated: 2026-11-23T12:56:27Z
+++

MetalSprocketsPBR (in SceneSprockets) shades with PBRMaterialUniforms and fixed texture slots. There is no defined way for a stitched MaterialX graph to supply base color, metallic, roughness, normal, emissive, occlusion, transmission, clearcoat, sheen, specular, iridescence, anisotropy etc. to that shader per pixel.

- `2026-11-23T12:56:27Z`: Question 1 (design): Compile each connected surface-shader input (base_color, metalness, specular_roughness, normal, emission, coat, ...) into one stitched function that fills a shared MXSurfaceInputs struct matching PBRMaterialUniforms fields? Recommended: Yes, one function writing a struct

---

## 35: MetalSprocketsPBR shaders have no hook for stitched material functions

+++
status: open
priority: critical
kind: feature
labels: effort:l, area:pbr, area:integration
depends: 34
created: 2026-11-23T12:40:29Z
updated: 2026-11-23T12:56:27Z
+++

PBR.metal reads material values from uniforms and textures directly. There is no visible-function call site (e.g. evaluate material inputs at a surface point) that a stitched MaterialX graph could be linked into, so stitched graphs cannot drive the existing PBR renderer. The change lives in SceneSprockets.

- `2026-11-23T12:56:27Z`: Question 1 (decision): Add an optional [[visible]] material-evaluation call to PBR.metal in SceneSprockets (function-constant gated, so materials without MaterialX pay nothing)? Recommended: Yes

---

## 36: standard_surface and open_pbr_surface parameters do not map one-to-one onto glTF PBR

+++
status: open
priority: high
kind: task
labels: effort:m, area:pbr, area:shading
depends: 34
created: 2026-11-23T12:40:29Z
updated: 2026-11-23T13:03:07Z
+++

Coat, sheen, subsurface, thin film, specular_anisotropy, transmission_depth/scatter etc. have no exact equivalent in glTF PBR. The bundled translation graphs (bxdf/translation/standard_surface_to_gltf_pbr.mtlx, open_pbr_to_standard_surface.mtlx) are not used, and the approximations to accept are undecided.

- `2026-11-23T13:03:07Z`: Question 1 (decision): Convert standard_surface/open_pbr_surface to glTF PBR inputs using the bundled translation nodegraphs (standard_surface_to_gltf_pbr.mtlx, open_pbr_to_standard_surface.mtlx), stitched like any functional graph, and accept their approximations (coat->clearcoat, sheen->sheen, subsurface dropped)? Recommended: Yes

---

## 37: Lights and environment from MetalSprocketsLighting are not available to MaterialX shaders

+++
status: open
priority: medium
kind: feature
labels: effort:l, area:pbr, area:lighting
depends: 22, 33
created: 2026-11-23T12:40:29Z
updated: 2026-11-23T13:38:54Z
+++

MaterialX surface shaders need light loops and IBL. MetalSprocketsLighting provides lights, shadows and environment for every renderer, but nothing connects it to MaterialX shading.

- `2026-11-23T13:38:54Z`: Question 1 (design): Should MaterialX surface shading reuse the lighting loop and IBL already in MetalSprocketsLighting/MetalSprocketsPBR (lit by the PBR renderer once #35 hooks stitched inputs in), instead of this package evaluating lights itself? Recommended: Yes, reuse the PBR renderer's lighting

---

## 38: Displacement and volume shaders are not supported

+++
status: open
priority: low
kind: feature
labels: effort:l, area:shading
depends: 22, 33
created: 2026-11-23T12:40:29Z
updated: 2026-11-23T13:35:07Z
+++

displacementshader, volumeshader and the displacement input on surfacematerial are ignored.

- `2026-11-23T13:35:07Z`: Question 1 (decision): Defer displacement and volume shaders until #22 (normal/position in the shading context) and #33 (shader closures) exist, since displacement needs a vertex-stage hook and volumes need closures? Recommended: Yes

---

## 39: Unlit and NPR shaders are not supported

+++
status: open
priority: low
kind: feature
labels: effort:m, area:shading
depends: 22, 33
created: 2026-11-23T12:40:29Z
updated: 2026-11-23T13:33:55Z
+++

surface_unlit, nprlib nodes (facingratio, viewdirection-based nodes) and gltf_unlit-style materials have no implementation.

- `2026-11-23T13:33:55Z`: Question 1 (decision): Wait for #22 (shading context with view direction/normal) and #33 (surfaceshader representation) before implementing surface_unlit and nprlib, since both need values the stitched signature does not carry yet? Recommended: Yes

---

## 40: Color management library (cmlib) is not implemented

+++
status: closed
priority: medium
kind: feature
labels: effort:m, area:color, area:nodes
created: 2026-11-23T12:40:29Z
updated: 2026-11-23T13:11:03Z
closed: 2026-11-23T13:11:03Z
+++

cmlib_defs.mtlx / cmlib_ng.mtlx colorspace transforms (srgb_texture_to_lin_rec709, acescg, etc.) have no Metal implementation, so colorspace conversions cannot happen inside graphs.

- `2026-11-23T13:11:03Z`: All 20 cmlib *_to_lin_rec709 transforms stitch through cmlib_ng.mtlx. Added power (all variants), transformmatrix (vector3/vector4/vector2M3/vector3M4), matrix33/44 constants and matrix parameters (one float4 slot per column, Parameter.slotCount). Tests: ColorManagementTests (sRGB decode and ACEScg matrix checked numerically).

---

## 41: No MetalSprockets element for rendering with a MaterialX material

+++
status: open
priority: high
kind: feature
labels: effort:l, area:metalsprockets, area:integration
depends: 22
created: 2026-11-23T12:40:29Z
updated: 2026-11-23T13:03:00Z
+++

MetalSprocketsMaterialX only exposes StitchedGraph.visibleFunction(). There is no Element or modifier that binds the parameter buffer, links the stitched function into a RenderPipeline, and updates parameters per frame.

- `2026-11-23T13:03:00Z`: Question 1 (design): Should the first MetalSprockets element be an unlit MaterialXSurface modifier (fragment shader calls the stitched base-color function, binds the parameter buffer, re-stitches only on topology change), with the lit PBR path waiting on #34/#35? Recommended: Yes, unlit first

---

## 42: SceneSprockets uses its own MaterialX loader instead of this library

+++
status: open
priority: high
kind: task
labels: effort:l, area:scenesprockets, area:integration
created: 2026-11-23T12:40:29Z
updated: 2026-11-23T12:55:47Z
+++

SceneSprockets has SceneSprocketsMaterialX (MaterialXDocument, its own XML parser and converter to PBRSceneMaterial, issues #528 #609 #620 there). This package duplicates the parser and aims to replace the per-pixel gaps listed in SceneSprockets #620. How the two meet (replace, wrap, or keep the CPU converter as a fallback) is undecided.

- `2026-11-23T13:03:12Z`: Question 1 (decision): Should SceneSprocketsMaterialX keep its CPU converter as a fallback and use this package's Document/StandardLibrary for parsing, switching to stitched per-pixel evaluation once #35 lands? Recommended: Yes

---

## 43: SceneSprockets cannot depend on this package without a dependency cycle check

+++
status: open
priority: medium
kind: task
labels: effort:s, area:scenesprockets, area:build
created: 2026-11-23T12:40:29Z
updated: 2026-11-23T12:55:47Z
+++

This package must not depend on SceneSprockets (SceneSprockets will depend on it), yet the PBR renderer it targets lives in SceneSprockets' MetalSprocketsPBR target. Where the PBR bridge code lives is undecided.

- `2026-11-23T13:16:20Z`: Question 1 (decision): Put the MaterialX→PBR bridge in SceneSprockets (e.g. extend SceneSprocketsMaterialX to depend on this package), keeping MetalSprocketsMaterialX free of any SceneSprockets dependency? Recommended: Yes

---

## 44: No hot reload of .mtlx files

+++
status: closed
priority: low
kind: feature
labels: effort:m, area:integration
created: 2026-11-23T12:40:29Z
updated: 2026-11-23T13:34:53Z
closed: 2026-11-23T13:34:53Z
+++

Editing a .mtlx file on disk does not update a running material. Re-stitching on change, and keeping parameter values when topology is unchanged, are not supported.

- `2026-11-23T13:34:53Z`: DocumentWatcher(url:).events() yields .loaded(Document) now and after each change to the file or any xi:include'd file (polls modification dates, so atomic saves work), or .failed for unparseable saves. StitchedGraph.carryParameters(from:) copies run-time edits (values differing from initialParameterData) into a re-stitched graph by name and type; values changed in the file win. Re-stitching reuses cached libraries when topology is unchanged (#27). Tests: DocumentWatcherTests, CarryParametersTests.

---

## 45: No relationship defined with MetalSprocketsShaderGraph

+++
status: open
priority: low
kind: task
labels: effort:s, area:integration
created: 2026-11-23T12:40:29Z
updated: 2026-11-23T12:55:47Z
+++

MetalSprocketsShaderGraph (node editor, own ShaderGraph.swift using function stitching) and MetalSprocketsAddOns' SimpleStitchedFunctionGraph overlap with this package. Whether ShaderGraph can load/save MaterialX or share the node library is not decided.

- `2026-11-23T13:35:24Z`: Question 1 (decision): Make MetalSprocketsShaderGraph use this package as its document format and node library (load/save .mtlx, node palette from StandardLibrary, compile with GraphStitcher), retire SimpleStitchedFunctionGraph in MetalSprocketsAddOns in favor of GraphStitcher, and build the MaterialX node editor (#56) on ShaderGraph's editor UI? Recommended: Yes

---

## 46: USD / RealityKit ShaderGraph (ND_RealityKit*) nodes are not supported

+++
status: open
priority: low
kind: feature
labels: effort:l, area:nodes, area:integration
created: 2026-11-23T12:40:29Z
updated: 2026-11-23T12:55:47Z
+++

Reality Composer Pro and USD files on this machine use Apple's MaterialX extensions (ShaderGraph.framework apple_nodedefs, CoreUSDEdit aapl nodes, ND_RealityKitTexture2D etc.). Documents that use them fail with missingNodeDef.

- `2026-11-23T13:35:18Z`: Apple's nodedefs are in /System/Library/SubFrameworks/ShaderGraph.framework/Versions/A/Resources/MaterialX/Apple/apple_nodedefs (14 files, ~1,450 nodedefs, MaterialX 1.38, generated). Their implementations are target="realitykit" function names with no source, and they use types the bundled libraries lack (integer2, ...). The files are Apple's and cannot be vendored.
- `2026-11-23T13:35:18Z`: Question 1 (design): Support RealityKit documents by loading Apple's nodedefs from the system ShaderGraph.framework at run time (opt-in, so they parse and validate) and implementing their Metal functions by hand, starting with the nodes the Reality Composer Pro sample assets actually use? Recommended: Yes, opt-in loading plus the most-used nodes first

---

## 47: No golden-image tests of rendered materials

+++
status: open
priority: high
kind: task
labels: effort:m, area:testing
depends: 41
created: 2026-11-23T12:40:29Z
updated: 2026-11-23T13:03:12Z
+++

There is no rendering test. GoldenImage is used by the other packages for this. The MaterialX test suite materials (resources/Materials/TestSuite in the MaterialX repo) are not on disk and are not vendored.

- `2026-11-23T13:03:12Z`: Question 1 (decision): Add golden-image tests (GoldenImage package) once #41 provides a render element, starting with a flat unlit quad per test material? Recommended: Yes

---

## 48: Real-world .mtlx corpus is limited to system library files

+++
status: closed
priority: medium
kind: task
labels: effort:m, area:testing
created: 2026-11-23T12:40:29Z
updated: 2026-11-23T13:28:53Z
closed: 2026-11-23T13:28:53Z
+++

Tests parse the .mtlx files under Reality Composer Pro's ShaderGraph.framework and /System/Library (found with locate). These are mostly definition libraries; there are no real material documents (GPUOpen MaterialX Library, ambientCG, Substance exports, MaterialX Examples) to test loading and stitching against.

- `2026-11-23T13:28:53Z`: Vendored a corpus: all 49 .mtlx files of MaterialX 1.39.4 resources/Materials/Examples (StandardSurface, OpenPbr, GltfPbr, UsdPreviewSurface, DisneyPrincipled, SimpleHair; no textures) plus SceneSprockets' demo Materials.mtlx. CorpusTests: every file parses and validates with no issues; every connected shader input stitches or fails only with unsupportedNode. Today 1 input stitches; the rest need image nodes (106, #18), rotate2d (3, #11) and string-typed inputs (2). Bugs found and fixed: vector values separated by spaces ('1 1,1' in SimpleHair; MaterialX accepts commas or spaces), and interface inputs of functional nodegraphs (declared on the nodedef) were reported missing by validate() and by the stitcher.

---

## 49: System .mtlx tests are skipped silently when Reality Composer Pro is absent

+++
status: closed
priority: low
kind: bug
labels: effort:xs, area:testing
created: 2026-11-23T12:40:29Z
updated: 2026-11-23T13:29:37Z
closed: 2026-11-23T13:29:37Z
+++

SystemMaterialXFiles.urls returns an empty list on machines without RCP or the system frameworks, so systemFileParses runs zero cases and still passes. CI would not notice.

- `2026-11-23T13:29:37Z`: systemFileParses is now .enabled(if: files exist) with a reason, so machines without RCP/system .mtlx files report it as skipped instead of passing with zero cases. The vendored corpus (#48) gives coverage that does not depend on installed apps. No failing-first test: absence of the files cannot be simulated without changing the machine.

---

## 50: Bundled MaterialX 1.39.4 libraries lack a license file and update process

+++
status: closed
priority: medium
kind: task
labels: effort:xs, area:build, area:legal
created: 2026-11-23T12:40:29Z
updated: 2026-11-23T13:15:01Z
closed: 2026-11-23T13:15:01Z
+++

Sources/MaterialX/Resources/libraries was copied from RealityComposerPro.app's ShaderGraph.framework (MaterialX 1.39.4, Apache-2.0). The Apache license and NOTICE are not included, and there is no script to update the libraries from upstream.

- `2026-11-23T13:15:01Z`: Added LICENSES/Apache-2.0.txt, NOTICE.md (MaterialX libraries, vendored genglsl impl map with its one fix, ported genglsl code, OSL notice for the HSV functions) and Scripts/update-materialx-libraries.sh (downloads a MaterialX release tag, copies the .mtlx libraries without gen* folders). Running it for v1.39.4 matched the Reality Composer Pro copy except for one file RCP lacked (targets/essl.mtlx), now included.

---

## 51: No SwiftLint config, CI or .xcb.toml

+++
status: closed
priority: medium
kind: task
labels: effort:s, area:build
created: 2026-11-23T12:40:29Z
updated: 2026-11-23T13:19:21Z
closed: 2026-11-23T13:19:21Z
+++

The package has no .swiftlint.yml, no GitHub Actions / Buildkite config and no .xcb.toml, unlike the sibling packages.

- `2026-11-23T13:19:21Z`: Added .swiftlint.yml (sibling packages' curated strict config; multiline strings excluded from indentation_width for test XML) with all violations fixed, .xcb.toml, and .github/workflows/swift.yml from 'xcb ci generate' (swiftlint, macOS build+test with warnings as errors, iOS and visionOS xcodebuild builds — which also covers #52 once CI runs).

---

## 52: No iOS / visionOS build verified

+++
status: open
priority: medium
kind: task
labels: effort:s, area:build
created: 2026-11-23T12:40:29Z
updated: 2026-11-23T12:55:47Z
+++

Package.swift declares iOS 26 and visionOS 26 but only macOS tests have run.

- `2026-11-23T13:18:15Z`: xcb builds Swift packages with 'swift build' even with -d ios / -d visionos (xcb build --dry-run --scheme MetalSprocketsMaterialX-Package -d visionos prints 'swift build'; same in MetalSprocketsParticles), so its 'Build succeeded' for those destinations is a macOS build and does not verify iOS/visionOS.
- `2026-11-23T13:18:15Z`: Question 1 (decision): May I run xcodebuild directly (-scheme MetalSprocketsMaterialX-Package -destination generic/platform=iOS and visionOS) for this check, since xcb only runs swift build for packages? Recommended: Yes, for this one-off verification

---

## 53: No README usage docs or DocC

+++
status: closed
priority: medium
kind: documentation
labels: effort:s, area:docs
created: 2026-11-23T12:40:29Z
updated: 2026-11-23T13:29:16Z
closed: 2026-11-23T13:29:16Z
+++

README is a stub. There is no usage example, architecture description (MaterialX → MaterialXMetal → MetalSprocketsMaterialX) or DocC catalog.

- `2026-11-23T13:29:16Z`: README rewritten: module table, usage (load, validate, merge custom nodedefs, stitch a graph output or a shader input, edit parameters, VisibleFunction), the stitched function's signature and parameter layout, private vs binary linking, how stitching works (naming, functional graph inlining, colorspace/units, caching, output sink), coverage baseline, dev commands. No DocC catalog yet; doc comments are kept minimal per house rules.

---

## 54: No demo app or example

+++
status: open
priority: low
kind: feature
labels: effort:m, area:docs
depends: 41
created: 2026-11-23T12:40:29Z
updated: 2026-11-23T13:35:00Z
+++

There is no example that loads a .mtlx file and renders it on a mesh with MetalSprockets, nor a DemoKit / MetalSprocketsExamples entry.

- `2026-11-23T13:35:00Z`: Question 1 (decision): Build the demo (a macOS app via 'xcb new' that loads a .mtlx with DocumentWatcher and shows each stitched output on a quad, plus the mtlx stitch report) after #41 provides the render element, rather than writing ad-hoc render code in the demo now? Recommended: Yes, after #41

---

## 55: No CLI to inspect and stitch .mtlx files

+++
status: closed
priority: low
kind: feature
labels: effort:s, area:tooling
created: 2026-11-23T12:40:29Z
updated: 2026-11-23T13:32:06Z
closed: 2026-11-23T13:32:06Z
+++

There is no command-line tool to list a document's materials and graphs, report unsupported nodes, or dump the stitched function and parameter layout.

- `2026-11-23T13:32:06Z`: New 'mtlx' executable (swift-argument-parser): list (materials, shaders with connected inputs, nodegraphs), validate (exit 1 on issues), stitch [--graph] (each nodegraph output and connected shader input: type, parameter layout and values, optional stitching graph dump, or the reason it fails; exit 1 on failures), coverage [--unsupported]. Checked by hand on the corpus; no unit tests for the CLI glue, which only calls tested library APIs.

---

## 56: No node editor for MaterialX graphs

+++
status: open
priority: medium
kind: feature
labels: area:tooling, area:integration, effort:xl
depends: 45
created: 2026-11-23T13:31:07Z
updated: 2026-11-23T13:38:12Z
+++

There is no visual editor for MaterialX documents. Users cannot see a nodegraph as nodes and wires, add or connect nodes from the bundled libraries, edit input values, or preview the result live.

Related:
- MetalSprocketsShaderGraph already has a node editor built on function stitching (see #45).
- Documents cannot be written back to .mtlx yet (#8), so edits could not be saved.
- Live preview needs a render element (#41).

---

## 57: Node implementation rules are duplicated across stitching, coverage and validation

+++
status: closed
priority: medium
kind: task
labels: area:architecture, effort:m
created: 2026-11-23T13:37:47Z
updated: 2026-11-23T13:40:33Z
closed: 2026-11-23T13:40:33Z
+++

Three places independently decide how a MaterialX node maps to an implementation:
- Builder.resolve in Sources/MaterialXMetal/GraphStitcher.swift
- GraphStitcher.coverage() in Sources/MaterialXMetal/NodeCoverage.swift
- Document.validate() in Sources/MaterialX/Validation.swift

Each repeats some of: nodedef selection, the ND_x → mx_x function naming rule, the _<output> suffix for multi-output nodes, the texcoord special case, the functional-nodegraph fallback, and interface-input lookup.

Consequences seen so far:
- The functional-nodegraph interface-input bug found in #48 had to be fixed in two places.
- coverage() reports a node as supported from a static walk that can disagree with what stitch() actually does (for example texcoord index != 0, colorspace inlining, value types without a parameter reader).

- `2026-11-23T13:38:12Z`: Related: #58 (both concern Builder in GraphStitcher.swift; a shared resolution step would touch both).
- `2026-11-23T13:40:33Z`: GraphStitcher.resolution(of:output:) is now the one place that decides function name, multi-output suffix, function vs functional nodegraph vs unsupported; stitch() and coverage() both use it. Validation keeps using StandardLibrary.nodeDef(for:) and interfaceInput(_:of:), which it already shared. New boundary test everyNodeDefStitchesExactlyWhenCoverageSaysSo stitches every single-output data nodedef and compares with coverage(); it failed before with 7 disagreements: ND_texcoord_vector3 (coverage claimed metal) and ND_blur_* (stitch resolved the unused string filtertype input and threw). Functional-graph inlining now binds only inputs with stitchable value types. Coverage baseline drops ND_texcoord_vector3.

---

## 58: Graph compilation cannot be inspected without a Metal device

+++
status: open
priority: medium
kind: task
labels: area:architecture, effort:l
created: 2026-11-23T13:37:47Z
updated: 2026-11-23T13:38:12Z
+++

Builder in Sources/MaterialXMetal/GraphStitcher.swift does graph traversal, parameter layout, colorspace and unit conversion, functional-graph inlining, cycle detection, the cache topology key, the debug description and MTLFunctionStitchingNode construction in one struct. Its only intermediate output is Metal stitching nodes.

Consequences:
- Every test of graph shape (which functions are called, parameter names and slots, inlining, colorspace wiring) needs a GPU and a stitched library.
- Logic bugs and Metal stitching failures surface through the same path, which made the stack-overflow crash found in #28 harder to locate.
- Upcoming signature changes (#22, #23) touch all of these concerns at once.

- `2026-11-23T13:38:12Z`: Related: #57 (node resolution duplicated in coverage and validation) and #61 (GPU-only checks).

---

## 59: Parameter buffer layout is spread over four places

+++
status: open
priority: low
kind: task
labels: area:architecture, effort:m
created: 2026-11-23T13:37:47Z
updated: 2026-11-23T13:38:12Z
+++

The layout of the constant-input buffer (one float4 slot per value, one per column for matrices, pointer advanced lazily between parameters) is encoded separately in:
- Builder.parameter / Builder.slots (GraphStitcher.swift)
- StitchedGraph: parameters, slot/slotCount, set(_:to:), carryParameters(from:), initialParameterData
- the Metal readers mx_parameter_* and mx_parameter_next (StandardLibrary.metal)
- the mtlx stitch command, which formats slots for display

All four must agree. Any layout change, such as the packing asked about in #24-Q1, has to edit all of them, and nothing checks that they stay consistent.

- `2026-11-23T13:38:12Z`: Related: #24 (parameter packing question #24-Q1 would change all four places).

---

## 60: Document is a raw XML tree plus eagerly copied typed views

+++
status: open
priority: low
kind: task
labels: area:architecture, effort:m, breaking
created: 2026-11-23T13:37:47Z
updated: 2026-11-23T13:38:12Z
+++

Document (Sources/MaterialX/Document.swift) builds nodeDefs, nodeGraphs and nodes from root once in init. Extensions in Looks.swift and Filenames.swift instead read root on every call. Node, Input and NodeGraph each keep a copy of their Element. Writer.swift serializes only the Element tree.

Consequences:
- Editing a document means mutating root and constructing a new Document; the typed views cannot be edited directly.
- The same information exists twice (typed fields and the element copy) and can drift.
- StandardLibrary.merging(_:) rebuilds the whole library from all documents for every merge.
- A node editor (#56) needs to edit documents in place.

- `2026-11-23T13:38:12Z`: Related: #56 (node editor needs in-place edits) and #10 (public type naming).

---

## 61: GPU evaluation of stitched graphs exists only as copied test code

+++
status: open
priority: low
kind: task
labels: area:architecture, effort:s
created: 2026-11-23T13:37:47Z
updated: 2026-11-23T13:38:12Z
+++

Running a stitched graph and reading its result back is implemented only in tests:
- StitchingTests.evaluate, called by about ten other suites
- separate copies of the same kernel and buffer setup in ReferenceImplementationTests and StitchingPerformanceTests

The kernel source hard-codes the stitched function signature, so #22 will need every copy updated. The mtlx CLI and debugging tools cannot evaluate a graph.

- `2026-11-23T13:38:12Z`: Related: #22 (signature change would update every copy) and #58.

---
