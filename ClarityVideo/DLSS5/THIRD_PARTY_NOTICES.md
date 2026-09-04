# DLSS 5 Port — Third-Party Notices

ClarityVideo's iOS/Metal implementation is not NVIDIA DLSS and does not redistribute NVIDIA NGX or DLSS runtime binaries.

## DLSS5-Feeder

The versioned feeder/build-frame architecture was studied and partially adapted from:

- Project: `jlrouzies-fr/DLSS5-Feeder`
- Copyright (c) 2026 Jean-Laurent ROUZIES
- License: MIT

Portions of that upstream project are themselves derived from `dlss5-dx11-bridge`, Copyright (c) 2026 NIGos, under the MIT License.

MIT License

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

## Apple Core ML Depth Anything V2 Small

The unsigned device build downloads and bundles Apple's `DepthAnythingV2SmallF16P6.mlpackage` from `apple/coreml-depth-anything-v2-small` on Hugging Face. It is used only to create monocular depth guidance for the experimental DLSS 5 feeder path.

- Model: Depth Anything V2 Small, Core ML F16 P6
- Publisher: Apple
- License: Apache License 2.0
- Upstream model authors: Lihe Yang et al.

The model remains subject to the Apache License 2.0 and its upstream notices. ClarityVideo does not claim authorship of the model.

## DLSS5-Image-Converter

`criso2hd-alt/DLSS5-Image-Converter` was used only as a behavioral/reference source for the standalone video/image feeder contract. Its source is source-available and is **not copied or redistributed** in ClarityVideo.

## NVIDIA

NVIDIA NGX headers/libraries and `nvngx_dlss.dll` / `nvngx_dlssnr.dll` are not included in ClarityVideo. They remain subject to NVIDIA's own terms and currently have no iOS/Metal ARM64 runtime supplied by this project.
