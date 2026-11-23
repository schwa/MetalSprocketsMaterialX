# Third-party notices

This package's own code is under the MIT license (`LICENSE`). It includes or ports the following.

## MaterialX

Copyright Contributors to the MaterialX Project. Licensed under the Apache License 2.0 (`LICENSES/Apache-2.0.txt`).
<https://github.com/AcademySoftwareFoundation/MaterialX>

- `Sources/MaterialX/Resources/libraries/`: the MaterialX 1.39.4 data libraries (`*.mtlx` only; the
  `gen*` shader-generator folders are not included), unmodified from the upstream `v1.39.4` release. Update with
  `Scripts/update-materialx-libraries.sh`.
- `Tests/MaterialXMetalTests/Resources/stdlib_genglsl_impl.mtlx`: MaterialX's GLSL implementation map, used as
  reference results. Modified: the unescaped `&&` in `IM_logical_and_genglsl` is written as `&amp;&amp;`.
- `Sources/MaterialXMetalShaders/Metal/StandardLibrary.metal`: node implementations ported from MaterialX's
  `genglsl` sources.
- `Tests/MaterialXMetalTests/Resources/Corpus/MaterialXExamples/`: the `.mtlx` files of MaterialX 1.39.4's
  `resources/Materials/Examples`, unmodified, without their textures.

## Open Shading Language

`mx_hsvtorgb` and `mx_rgbtohsv` in `StandardLibrary.metal` are ported from MaterialX's `mx_hsv.glsl`, which is
derived from Open Shading Language's `opcolor.cpp`, and `Noise.metal` is ported from MaterialX's `mx_noise.glsl`,
which is derived from Open Shading Language's `oslnoise.h`. Both carry this notice:

> Copyright (c) 2009-2010 Sony Pictures Imageworks Inc., et al. All Rights Reserved.
>
> Redistribution and use in source and binary forms, with or without modification, are permitted provided that the
> following conditions are met: Redistributions of source code must retain the above copyright notice, this list of
> conditions and the following disclaimer. Redistributions in binary form must reproduce the above copyright notice,
> this list of conditions and the following disclaimer in the documentation and/or other materials provided with the
> distribution. Neither the name of Sony Pictures Imageworks nor the names of its contributors may be used to endorse
> or promote products derived from this software without specific prior written permission.
>
> THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES,
> INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
> DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
> SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
> SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
> WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
> OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
