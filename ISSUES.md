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
status: open
priority: low
kind: feature
labels: effort:m, area:document
created: 2026-11-23T12:40:29Z
updated: 2026-11-23T12:55:47Z
+++

<look>, <materialassign>, <collection>, <geominfo>, <propertyset> and <variantset> are skipped by Document. Material assignment by geometry name and variant selection are unavailable.

---

## 8: Documents cannot be written back to .mtlx

+++
status: open
priority: low
kind: feature
labels: effort:m, area:document
created: 2026-11-23T12:40:29Z
updated: 2026-11-23T12:55:47Z
+++

Document and Element are read-only. There is no serializer, so tools cannot edit a material and save it.

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
status: open
priority: medium
kind: feature
labels: effort:l, area:nodes
created: 2026-11-23T12:40:29Z
updated: 2026-11-23T12:55:47Z
+++

remap, smoothstep, luminance, rgbtohsv, hsvtorgb, contrast, range, hsvadjust, saturate, colorcorrect, premult, unpremult, plus, minus, difference, burn, dodge, screen, overlay, disjointover, in, mask, matte, out, over, inside, outside have no implementation.

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
status: open
priority: medium
kind: task
labels: effort:s, area:nodes, area:testing
created: 2026-11-23T12:40:29Z
updated: 2026-11-23T12:55:47Z
+++

There is no report of which nodedefs in the bundled libraries have a Metal function, a nodegraph implementation, or neither. Coverage regressions go unnoticed.

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
status: open
priority: medium
kind: task
labels: effort:m, area:stitching, area:performance
created: 2026-11-23T12:40:29Z
updated: 2026-11-23T12:55:47Z
+++

No numbers for stitch time, pipeline link time (binary vs static linking), or GPU time of a stitched material compared with hand-written or MaterialX-generated MSL. MetalSprocketsParticles has a stitching timing harness that could be compared with.

---

## 29: Stitching errors are hard to diagnose

+++
status: open
priority: low
kind: enhancement
labels: effort:s, area:stitching
created: 2026-11-23T12:40:29Z
updated: 2026-11-23T12:55:47Z
+++

When makeLibrary(stitchedDescriptor:) fails, the error names the stitching graph only. There is no way to dump the graph (nodes, argument wiring, types) for debugging.

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

---

## 31: Node library is compiled by SwiftPM's default .metal processing

+++
status: open
priority: medium
kind: task
labels: effort:s, area:build, area:shaders
created: 2026-11-23T12:40:29Z
updated: 2026-11-23T12:55:47Z
+++

StandardLibrary.metal is a .process resource compiled into the target bundle's default.metallib. Other packages in this family use MetalCompilerPlugin with a bundle finder, debug metallibs and shared headers. Whether the default path works under Xcode builds, visionOS and iOS is untested.

---

## 32: Unused stitching graph arguments change the stitched signature

+++
status: open
priority: low
kind: documentation
labels: effort:xs, area:stitching
created: 2026-11-23T12:40:29Z
updated: 2026-11-23T12:55:47Z
+++

Found during bootstrap: MTLFunctionStitchingGraph drops input arguments that no node reads, so a graph that ignores texcoord compiled as T(constant float4 *) and the caller read garbage. The mx_output_* sink nodes work around it. This is not documented in the README, and there is no test for a graph that reads neither argument.

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
created: 2026-11-23T12:40:29Z
updated: 2026-11-23T12:55:47Z
+++

MaterialX surface shaders need light loops and IBL. MetalSprocketsLighting provides lights, shadows and environment for every renderer, but nothing connects it to MaterialX shading.

---

## 38: Displacement and volume shaders are not supported

+++
status: open
priority: low
kind: feature
labels: effort:l, area:shading
created: 2026-11-23T12:40:29Z
updated: 2026-11-23T12:55:47Z
+++

displacementshader, volumeshader and the displacement input on surfacematerial are ignored.

---

## 39: Unlit and NPR shaders are not supported

+++
status: open
priority: low
kind: feature
labels: effort:m, area:shading
created: 2026-11-23T12:40:29Z
updated: 2026-11-23T12:55:47Z
+++

surface_unlit, nprlib nodes (facingratio, viewdirection-based nodes) and gltf_unlit-style materials have no implementation.

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

---

## 44: No hot reload of .mtlx files

+++
status: open
priority: low
kind: feature
labels: effort:m, area:integration
created: 2026-11-23T12:40:29Z
updated: 2026-11-23T12:55:47Z
+++

Editing a .mtlx file on disk does not update a running material. Re-stitching on change, and keeping parameter values when topology is unchanged, are not supported.

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
status: open
priority: medium
kind: task
labels: effort:m, area:testing
created: 2026-11-23T12:40:29Z
updated: 2026-11-23T12:55:47Z
+++

Tests parse the .mtlx files under Reality Composer Pro's ShaderGraph.framework and /System/Library (found with locate). These are mostly definition libraries; there are no real material documents (GPUOpen MaterialX Library, ambientCG, Substance exports, MaterialX Examples) to test loading and stitching against.

---

## 49: System .mtlx tests are skipped silently when Reality Composer Pro is absent

+++
status: open
priority: low
kind: bug
labels: effort:xs, area:testing
created: 2026-11-23T12:40:29Z
updated: 2026-11-23T12:55:47Z
+++

SystemMaterialXFiles.urls returns an empty list on machines without RCP or the system frameworks, so systemFileParses runs zero cases and still passes. CI would not notice.

---

## 50: Bundled MaterialX 1.39.4 libraries lack a license file and update process

+++
status: open
priority: medium
kind: task
labels: effort:xs, area:build, area:legal
created: 2026-11-23T12:40:29Z
updated: 2026-11-23T12:55:47Z
+++

Sources/MaterialX/Resources/libraries was copied from RealityComposerPro.app's ShaderGraph.framework (MaterialX 1.39.4, Apache-2.0). The Apache license and NOTICE are not included, and there is no script to update the libraries from upstream.

---

## 51: No SwiftLint config, CI or .xcb.toml

+++
status: open
priority: medium
kind: task
labels: effort:s, area:build
created: 2026-11-23T12:40:29Z
updated: 2026-11-23T12:55:47Z
+++

The package has no .swiftlint.yml, no GitHub Actions / Buildkite config and no .xcb.toml, unlike the sibling packages.

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

---

## 53: No README usage docs or DocC

+++
status: open
priority: medium
kind: documentation
labels: effort:s, area:docs
created: 2026-11-23T12:40:29Z
updated: 2026-11-23T12:55:47Z
+++

README is a stub. There is no usage example, architecture description (MaterialX → MaterialXMetal → MetalSprocketsMaterialX) or DocC catalog.

---

## 54: No demo app or example

+++
status: open
priority: low
kind: feature
labels: effort:m, area:docs
created: 2026-11-23T12:40:29Z
updated: 2026-11-23T12:55:47Z
+++

There is no example that loads a .mtlx file and renders it on a mesh with MetalSprockets, nor a DemoKit / MetalSprocketsExamples entry.

---

## 55: No CLI to inspect and stitch .mtlx files

+++
status: open
priority: low
kind: feature
labels: effort:s, area:tooling
created: 2026-11-23T12:40:29Z
updated: 2026-11-23T12:55:47Z
+++

There is no command-line tool to list a document's materials and graphs, report unsupported nodes, or dump the stitched function and parameter layout.

---
