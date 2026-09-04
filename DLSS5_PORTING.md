# DLSS 5 iOS Rehosting Track

This branch keeps two separate goals:

1. make ClarityVideo's existing Apple `VTFrameProcessor` video path reliable on physical iOS devices;
2. build the resource contract and backend boundary needed to investigate a genuine DLSS 5 rehost without falsely labeling an Apple/Core Image fallback as NVIDIA DLSS.

## Reference architecture

The useful open-source reference is `jlrouzies-fr/DLSS5-Feeder` (MIT). Its architecture constructs a DLSS/DLAA-style evaluation contract from ordinary image/video inputs, including color, depth, motion vectors, frame dimensions, temporal state, and the NGX evaluation call. That is the portion whose *interface and data flow* are useful to ClarityVideo.

The current NVIDIA execution boundary is still the blocker. Existing DLSS 5 injectors ultimately rely on NVIDIA's proprietary NGX/DLSS neural-rendering runtime, Windows/D3D12, and NVIDIA GPU execution. An iOS arm64 app cannot load `nvngx_dlssnr.dll`, and ClarityVideo will not ship that binary or claim that an Apple implementation is the NVIDIA runtime.

## ClarityVideo contract

`ClarityVideo/DLSS5/DLSS5ReferenceContract.swift` defines the feeder-facing resource contract:

- color: RGBA16Float
- depth: R32Float
- motion: RG16Float, expressed in pixel-space
- render dimensions
- output dimensions
- temporal reset flag
- zero-jitter baseline matching the current video-feeder experiment
- reversed-depth flag

This lets the iOS side build and validate the same class of inputs while the execution backend is researched independently.

## Next execution milestones

- Generate Apple optical flow for consecutive video frames and convert it into the feeder's RG16Float pixel-motion convention.
- Add a real monocular-depth model/resource provider and normalize it to the feeder's reversed-depth convention.
- Add reference-frame capture files so the exact same color/depth/motion packet can be evaluated on an RTX Windows reference harness and compared against the iPhone-side preparation output.
- Keep NVIDIA runtime execution behind a capability probe. Do not expose a DLSS 5 UI selector until that probe can execute a genuine compatible backend.
- If an ARM64/Metal reimplementation is developed, validate still frames first, then temporal video, then wire the resulting backend into ClarityVideo's existing decode/encode pipeline.

## Licensing boundary

Do not copy or redistribute NVIDIA runtime binaries. Do not copy source from projects whose license does not permit it. Use MIT/open-source feeder code only within its license and keep third-party notices with any incorporated code.
