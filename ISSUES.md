# ISSUES.md

File format: <https://github.com/schwa/issues-format>

---

## 1: xi:include elements are not followed

+++
status: new
priority: high
kind: feature
labels: document
created: 2026-11-23T12:40:29Z
+++

Documents that split definitions across files with <xi:include href=...> load only the top file. Included nodedefs, nodegraphs and materials are missing. Relative hrefs, search paths and include cycles are not handled.

---

## 2: Nodedef inheritance (inherit attribute) is not resolved

+++
status: new
priority: high
kind: feature
labels: document
created: 2026-11-23T12:40:29Z
+++

Nodedefs such as ND_standard_surface_surfaceshader declare inherit="ND_standard_surface_surfaceshader_100". The inherited inputs and outputs are not merged, so a node matched to the child nodedef only sees the child's own inputs.

---

## 3: Nodedef versioning is ignored

+++
status: new
priority: medium
kind: feature
labels: document
created: 2026-11-23T12:40:29Z
+++

MaterialX nodedefs have version and isdefaultversion attributes, and nodes can request a version. StandardLibrary picks a nodedef by category and types only, so a document that asks for an older version of a node gets an arbitrary one.

---

## 4: Type defaults and typedefs are not modelled

+++
status: new
priority: medium
kind: feature
labels: document
created: 2026-11-23T12:40:29Z
+++

ValueType is a string wrapper. Custom <typedef> elements, struct types (1.39), multi-output types and the semantic and context attributes are not read. Integer and boolean inputs parse as floats.

---

## 5: Unit and colorspace attributes are not applied

+++
status: new
priority: medium
kind: feature
labels: document, color
created: 2026-11-23T12:40:29Z
+++

colorspace on the document, nodegraph, image and input values, and unit / unittype on distance and angle inputs, are parsed into attributes but have no effect. Values and textures in srgb_texture, acescg, lin_rec709 etc. are used as if already in the working space.

---

## 6: Tokens and string substitution in filenames are not resolved

+++
status: new
priority: medium
kind: feature
labels: document
created: 2026-11-23T12:40:29Z
+++

<token> elements and [token] substitution in filename values (e.g. textures/[albedo].png), the fileprefix attribute inherited from ancestors, and UDIM <UDIM> / <UVTILE> patterns are not resolved.

---

## 7: Looks, collections, geominfo and variants are not loaded

+++
status: new
priority: low
kind: feature
labels: document
created: 2026-11-23T12:40:29Z
+++

<look>, <materialassign>, <collection>, <geominfo>, <propertyset> and <variantset> are skipped by Document. Material assignment by geometry name and variant selection are unavailable.

---

## 8: Documents cannot be written back to .mtlx

+++
status: new
priority: low
kind: feature
labels: document
created: 2026-11-23T12:40:29Z
+++

Document and Element are read-only. There is no serializer, so tools cannot edit a material and save it.

---

## 9: No document validation

+++
status: new
priority: medium
kind: feature
labels: document
created: 2026-11-23T12:40:29Z
+++

Documents are trusted as given. There is no check for dangling nodename references, type mismatches between connected inputs and outputs, unknown categories, or interfacename pointing at missing inputs, so errors only appear at stitch time or not at all.

---

## 10: Swift API surface of the MaterialX module needs a design pass

+++
status: new
priority: medium
kind: task
labels: document, api
created: 2026-11-23T12:40:29Z
+++

Types are named Element, Node, Input, Output, Value, Document in module MaterialX. They clash easily with other modules imported by SceneSprockets and MetalSprockets (e.g. Node in SceneSprockets). Naming, Sendable, Codable and mutability were picked quickly during bootstrap.

---

## 11: Most stdlib math nodes have no Metal implementation

+++
status: new
priority: high
kind: feature
labels: nodes, stitching
created: 2026-11-23T12:40:29Z
+++

StandardLibrary.metal covers add, subtract, multiply, divide, min, max, mix, combine3 and two converts. stdlib_defs.mtlx has ~690 nodedefs. Missing math: modulo, fract, invert, absval, sign, floor, ceil, round, power, safepower, sin/cos/tan/asin/acos/atan2, sqrt, ln, exp, clamp, normalize, magnitude, distance, dotproduct, crossproduct, transformpoint/vector/normal, transformmatrix, normalmap, creatematrix, transpose, determinant, invertmatrix, rotate2d, rotate3d, reflect, refract, place2d, trianglewave, etc.

---

## 12: Channel and conversion nodes are missing

+++
status: new
priority: high
kind: feature
labels: nodes
created: 2026-11-23T12:40:29Z
+++

extract, separate2/3/4, combine2/4, swizzle (1.38 compat), convert for all type pairs, and the FA/vector variants are mostly absent from StandardLibrary.metal.

---

## 13: Logical and conditional nodes are missing

+++
status: new
priority: medium
kind: feature
labels: nodes
created: 2026-11-23T12:40:29Z
+++

ifgreater, ifgreatereq, ifequal, switch, and/or/not/xor (1.39 boolean nodes) have no implementation. Boolean and integer inputs also have no parameter readers.

---

## 14: Adjustment and compositing nodes are missing

+++
status: new
priority: medium
kind: feature
labels: nodes
created: 2026-11-23T12:40:29Z
+++

remap, smoothstep, luminance, rgbtohsv, hsvtorgb, contrast, range, hsvadjust, saturate, colorcorrect, premult, unpremult, plus, minus, difference, burn, dodge, screen, overlay, disjointover, in, mask, matte, out, over, inside, outside have no implementation.

---

## 15: Procedural pattern nodes are missing

+++
status: new
priority: high
kind: feature
labels: nodes
created: 2026-11-23T12:40:29Z
+++

noise2d, noise3d, fractal2d/3d, cellnoise2d/3d, worleynoise2d/3d, unifiednoise2d/3d, ramplr, ramptb, ramp4, splitlr, splittb, randomfloat, randomcolor, checkerboard, line, circle, cloverleaf, hexagon, grid, crosshatch, tiledcircles, tiledcloverleafs, tiledhexagons, bump have no implementation. MaterialX's genmsl lib (mx_noise.metal etc.) is available on disk for reference.

---

## 16: Geometric nodes other than texcoord are missing

+++
status: new
priority: high
kind: feature
labels: nodes, geometry
created: 2026-11-23T12:40:29Z
+++

position, normal, tangent, bitangent, geomcolor, geompropvalue, time, frame, viewdirection and the space input (model/object/world) are not available. The stitched function only receives a texture coordinate.

---

## 17: texcoord index input is ignored

+++
status: new
priority: medium
kind: bug
labels: nodes, geometry
created: 2026-11-23T12:40:29Z
+++

texcoord nodes always read the single texcoord argument; index=1 (second UV set) behaves like index=0.

---

## 18: Image and texture nodes are not supported

+++
status: new
priority: critical
kind: feature
labels: nodes, textures
created: 2026-11-23T12:40:29Z
+++

image, tiledimage, triplanarprojection, hextiledimage, gltf_image/gltf_colorimage/gltf_normalmap and their uaddressmode, vaddressmode, filtertype, framerange, frameoffset, frameendaction, default and texcoord inputs have no implementation. Stitched functions have no way to reach textures or samplers today.

---

## 19: Functional nodegraphs (*_ng.mtlx) are not used as node implementations

+++
status: new
priority: high
kind: feature
labels: nodes, stitching
created: 2026-11-23T12:40:29Z
+++

Many nodedefs are implemented in stdlib_ng.mtlx / pbrlib_ng.mtlx as nodegraphs rather than source. StandardLibrary loads them but GraphStitcher does not inline a nodegraph implementation when a node has no Metal function, so those nodes fail with unsupportedNode.

---

## 20: Node coverage is not tracked

+++
status: new
priority: medium
kind: task
labels: nodes, testing
created: 2026-11-23T12:40:29Z
+++

There is no report of which nodedefs in the bundled libraries have a Metal function, a nodegraph implementation, or neither. Coverage regressions go unnoticed.

---

## 21: Node implementations are not checked against MaterialX reference results

+++
status: new
priority: high
kind: task
labels: nodes, testing
created: 2026-11-23T12:40:29Z
+++

Each Metal node implementation is written by hand. Nothing compares its output against MaterialX's own genmsl/genglsl implementations or reference renders for the same inputs.

---

## 22: Stitched graph signature only carries texcoord and parameters

+++
status: new
priority: critical
kind: feature
labels: stitching, geometry
created: 2026-11-23T12:40:29Z
+++

The stitched function is T(float2 texcoord, constant float4 *parameters). There is no way to pass position, normal, tangent, view direction, time, vertex color, or multiple UV sets. Changing it later breaks every caller, so the shading context needs to be designed before more nodes are added.

---

## 23: Textures and samplers cannot be passed through stitched graphs

+++
status: new
priority: critical
kind: feature
labels: stitching, textures
created: 2026-11-23T12:40:29Z
+++

Image nodes need texture and sampler access. Whether [[stitchable]] functions can take texture2d/sampler arguments or must go through an argument buffer, and how that interacts with residency in MetalSprockets, is not investigated.

---

## 24: Parameter buffer layout wastes space and has no typed access

+++
status: new
priority: low
kind: enhancement
labels: stitching
created: 2026-11-23T12:40:29Z
+++

Every parameter takes one float4 slot, including floats. parameterData is [SIMD4<Float>] indexed by slot number; there is no typed setter by name (e.g. set("tint", to: SIMD3)) and no validation of type on write.

---

## 25: Multi-output nodes and nodegraph outputs are not supported

+++
status: new
priority: high
kind: feature
labels: stitching
created: 2026-11-23T12:40:29Z
+++

Nodes with several outputs (separate3, artistic_ior, gltf_* nodes) and inputs with output="..." are ignored by GraphStitcher. stitch() also compiles one nodegraph output at a time; a surface shader with many connected inputs needs one function per input or one function with several results.

---

## 26: Top-level nodes and nodegraph references from shader inputs are not stitched

+++
status: new
priority: high
kind: feature
labels: stitching
created: 2026-11-23T12:40:29Z
+++

GraphStitcher compiles a NodeGraph only. Shader inputs connected with nodegraph=... output=..., or to nodes declared at document level (outside any nodegraph), cannot be compiled.

---

## 27: Stitched libraries are not cached

+++
status: new
priority: medium
kind: enhancement
labels: stitching, performance
created: 2026-11-23T12:40:29Z
+++

Every stitch() call builds a new MTLStitchedLibrary. Two materials with the same graph topology but different constant values produce identical libraries. There is no cache keyed by topology, and no measurement of stitch cost per graph size.

---

## 28: Stitching cost and runtime performance are unmeasured

+++
status: new
priority: medium
kind: task
labels: stitching, performance
created: 2026-11-23T12:40:29Z
+++

No numbers for stitch time, pipeline link time (binary vs static linking), or GPU time of a stitched material compared with hand-written or MaterialX-generated MSL. MetalSprocketsParticles has a stitching timing harness that could be compared with.

---

## 29: Stitching errors are hard to diagnose

+++
status: new
priority: low
kind: enhancement
labels: stitching
created: 2026-11-23T12:40:29Z
+++

When makeLibrary(stitchedDescriptor:) fails, the error names the stitching graph only. There is no way to dump the graph (nodes, argument wiring, types) for debugging.

---

## 30: Constant folding before stitching is not done

+++
status: new
priority: low
kind: enhancement
labels: stitching, performance
created: 2026-11-23T12:40:29Z
+++

Subgraphs that depend only on constants are stitched as function calls and evaluated per pixel. SceneSprocketsMaterialX already folds math on constants on the CPU (#609 in SceneSprockets).

---

## 31: Node library is compiled by SwiftPM's default .metal processing

+++
status: new
priority: medium
kind: task
labels: build, shaders
created: 2026-11-23T12:40:29Z
+++

StandardLibrary.metal is a .process resource compiled into the target bundle's default.metallib. Other packages in this family use MetalCompilerPlugin with a bundle finder, debug metallibs and shared headers. Whether the default path works under Xcode builds, visionOS and iOS is untested.

---

## 32: Unused stitching graph arguments change the stitched signature

+++
status: new
priority: low
kind: documentation
labels: stitching
created: 2026-11-23T12:40:29Z
+++

Found during bootstrap: MTLFunctionStitchingGraph drops input arguments that no node reads, so a graph that ignores texcoord compiled as T(constant float4 *) and the caller read garbage. The mx_output_* sink nodes work around it. This is not documented in the README, and there is no test for a graph that reads neither argument.

---

## 33: No surface shader evaluation (standard_surface, open_pbr_surface, gltf_pbr, UsdPreviewSurface)

+++
status: new
priority: critical
kind: feature
labels: pbr, shading
created: 2026-11-23T12:40:29Z
+++

The library compiles pattern graphs only. Surface shader nodes and their BSDF/EDF/VDF closures (pbrlib: oren_nayar_diffuse_bsdf, dielectric_bsdf, conductor_bsdf, generalized_schlick_bsdf, subsurface_bsdf, sheen_bsdf, thin_film_bsdf, layer, mix, add, multiply, uniform_edf, ...) have no Metal representation.

---

## 34: No mapping from MaterialX surface shaders to MetalSprocketsPBR material inputs

+++
status: new
priority: critical
kind: feature
labels: pbr, integration
created: 2026-11-23T12:40:29Z
+++

MetalSprocketsPBR (in SceneSprockets) shades with PBRMaterialUniforms and fixed texture slots. There is no defined way for a stitched MaterialX graph to supply base color, metallic, roughness, normal, emissive, occlusion, transmission, clearcoat, sheen, specular, iridescence, anisotropy etc. to that shader per pixel.

---

## 35: MetalSprocketsPBR shaders have no hook for stitched material functions

+++
status: new
priority: critical
kind: feature
labels: pbr, integration
created: 2026-11-23T12:40:29Z
+++

PBR.metal reads material values from uniforms and textures directly. There is no visible-function call site (e.g. evaluate material inputs at a surface point) that a stitched MaterialX graph could be linked into, so stitched graphs cannot drive the existing PBR renderer. The change lives in SceneSprockets.

---

## 36: standard_surface and open_pbr_surface parameters do not map one-to-one onto glTF PBR

+++
status: new
priority: high
kind: task
labels: pbr, shading
created: 2026-11-23T12:40:29Z
+++

Coat, sheen, subsurface, thin film, specular_anisotropy, transmission_depth/scatter etc. have no exact equivalent in glTF PBR. The bundled translation graphs (bxdf/translation/standard_surface_to_gltf_pbr.mtlx, open_pbr_to_standard_surface.mtlx) are not used, and the approximations to accept are undecided.

---

## 37: Lights and environment from MetalSprocketsLighting are not available to MaterialX shaders

+++
status: new
priority: medium
kind: feature
labels: pbr, lighting
created: 2026-11-23T12:40:29Z
+++

MaterialX surface shaders need light loops and IBL. MetalSprocketsLighting provides lights, shadows and environment for every renderer, but nothing connects it to MaterialX shading.

---

## 38: Displacement and volume shaders are not supported

+++
status: new
priority: low
kind: feature
labels: shading
created: 2026-11-23T12:40:29Z
+++

displacementshader, volumeshader and the displacement input on surfacematerial are ignored.

---

## 39: Unlit and NPR shaders are not supported

+++
status: new
priority: low
kind: feature
labels: shading
created: 2026-11-23T12:40:29Z
+++

surface_unlit, nprlib nodes (facingratio, viewdirection-based nodes) and gltf_unlit-style materials have no implementation.

---

## 40: Color management library (cmlib) is not implemented

+++
status: new
priority: medium
kind: feature
labels: color, nodes
created: 2026-11-23T12:40:29Z
+++

cmlib_defs.mtlx / cmlib_ng.mtlx colorspace transforms (srgb_texture_to_lin_rec709, acescg, etc.) have no Metal implementation, so colorspace conversions cannot happen inside graphs.

---

## 41: No MetalSprockets element for rendering with a MaterialX material

+++
status: new
priority: high
kind: feature
labels: metalsprockets, integration
created: 2026-11-23T12:40:29Z
+++

MetalSprocketsMaterialX only exposes StitchedGraph.visibleFunction(). There is no Element or modifier that binds the parameter buffer, links the stitched function into a RenderPipeline, and updates parameters per frame.

---

## 42: SceneSprockets uses its own MaterialX loader instead of this library

+++
status: new
priority: high
kind: task
labels: scenesprockets, integration
created: 2026-11-23T12:40:29Z
+++

SceneSprockets has SceneSprocketsMaterialX (MaterialXDocument, its own XML parser and converter to PBRSceneMaterial, issues #528 #609 #620 there). This package duplicates the parser and aims to replace the per-pixel gaps listed in SceneSprockets #620. How the two meet (replace, wrap, or keep the CPU converter as a fallback) is undecided.

---

## 43: SceneSprockets cannot depend on this package without a dependency cycle check

+++
status: new
priority: medium
kind: task
labels: scenesprockets, build
created: 2026-11-23T12:40:29Z
+++

This package must not depend on SceneSprockets (SceneSprockets will depend on it), yet the PBR renderer it targets lives in SceneSprockets' MetalSprocketsPBR target. Where the PBR bridge code lives is undecided.

---

## 44: No hot reload of .mtlx files

+++
status: new
priority: low
kind: feature
labels: integration
created: 2026-11-23T12:40:29Z
+++

Editing a .mtlx file on disk does not update a running material. Re-stitching on change, and keeping parameter values when topology is unchanged, are not supported.

---

## 45: No relationship defined with MetalSprocketsShaderGraph

+++
status: new
priority: low
kind: task
labels: integration
created: 2026-11-23T12:40:29Z
+++

MetalSprocketsShaderGraph (node editor, own ShaderGraph.swift using function stitching) and MetalSprocketsAddOns' SimpleStitchedFunctionGraph overlap with this package. Whether ShaderGraph can load/save MaterialX or share the node library is not decided.

---

## 46: USD / RealityKit ShaderGraph (ND_RealityKit*) nodes are not supported

+++
status: new
priority: low
kind: feature
labels: nodes, integration
created: 2026-11-23T12:40:29Z
+++

Reality Composer Pro and USD files on this machine use Apple's MaterialX extensions (ShaderGraph.framework apple_nodedefs, CoreUSDEdit aapl nodes, ND_RealityKitTexture2D etc.). Documents that use them fail with missingNodeDef.

---

## 47: No golden-image tests of rendered materials

+++
status: new
priority: high
kind: task
labels: testing
created: 2026-11-23T12:40:29Z
+++

There is no rendering test. GoldenImage is used by the other packages for this. The MaterialX test suite materials (resources/Materials/TestSuite in the MaterialX repo) are not on disk and are not vendored.

---

## 48: Real-world .mtlx corpus is limited to system library files

+++
status: new
priority: medium
kind: task
labels: testing
created: 2026-11-23T12:40:29Z
+++

Tests parse the .mtlx files under Reality Composer Pro's ShaderGraph.framework and /System/Library (found with locate). These are mostly definition libraries; there are no real material documents (GPUOpen MaterialX Library, ambientCG, Substance exports, MaterialX Examples) to test loading and stitching against.

---

## 49: System .mtlx tests are skipped silently when Reality Composer Pro is absent

+++
status: new
priority: low
kind: bug
labels: testing
created: 2026-11-23T12:40:29Z
+++

SystemMaterialXFiles.urls returns an empty list on machines without RCP or the system frameworks, so systemFileParses runs zero cases and still passes. CI would not notice.

---

## 50: Bundled MaterialX 1.39.4 libraries lack a license file and update process

+++
status: new
priority: medium
kind: task
labels: build, legal
created: 2026-11-23T12:40:29Z
+++

Sources/MaterialX/Resources/libraries was copied from RealityComposerPro.app's ShaderGraph.framework (MaterialX 1.39.4, Apache-2.0). The Apache license and NOTICE are not included, and there is no script to update the libraries from upstream.

---

## 51: No SwiftLint config, CI or .xcb.toml

+++
status: new
priority: medium
kind: task
labels: build
created: 2026-11-23T12:40:29Z
+++

The package has no .swiftlint.yml, no GitHub Actions / Buildkite config and no .xcb.toml, unlike the sibling packages.

---

## 52: No iOS / visionOS build verified

+++
status: new
priority: medium
kind: task
labels: build
created: 2026-11-23T12:40:29Z
+++

Package.swift declares iOS 26 and visionOS 26 but only macOS tests have run.

---

## 53: No README usage docs or DocC

+++
status: new
priority: medium
kind: documentation
labels: docs
created: 2026-11-23T12:40:29Z
+++

README is a stub. There is no usage example, architecture description (MaterialX → MaterialXMetal → MetalSprocketsMaterialX) or DocC catalog.

---

## 54: No demo app or example

+++
status: new
priority: low
kind: feature
labels: docs
created: 2026-11-23T12:40:29Z
+++

There is no example that loads a .mtlx file and renders it on a mesh with MetalSprockets, nor a DemoKit / MetalSprocketsExamples entry.

---

## 55: No CLI to inspect and stitch .mtlx files

+++
status: new
priority: low
kind: feature
labels: tooling
created: 2026-11-23T12:40:29Z
+++

There is no command-line tool to list a document's materials and graphs, report unsupported nodes, or dump the stitched function and parameter layout.

---
