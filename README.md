# Clarity Video AI

Clarity Video AI is a native SwiftUI iOS 26 app for private, fully on-device video enhancement and UHD export. It imports videos from Photos or Files, analyzes the real media, uses Apple's public `VTFrameProcessor` effects, and produces an unsigned arm64 device IPA through GitHub Actions on `macos-26`.

## Implemented

- Photos and security-scoped Files import into a private app workspace
- Encoded/display resolution, transform, frame rate, codec, HDR, duration, and file-size inspection
- Device probes for Apple full-quality SR, low-latency SR, temporal denoise, model status/revisions, HEVC 4K/8K, and Main10
- Explicit Apple model download plus a one-frame neural self-test in Diagnostics
- Persistent full-quality or low-latency `VTFrameProcessor` sessions across the frame loop
- Actual Apple temporal noise filtering, driven by the denoise control
- Luma-based scene-cut detection with temporal-history reset
- Fixed overlapping AI tiles reconstructed by a Metal raised-cosine blend kernel
- Honest lower-memory AI-plus-Lanczos fallback when the supported neural factor cannot directly reach the target
- Core Image detail-recovery and sharpening controls in the encoded frame path
- Exact 3840x2160 / 7680x4320 output, portrait transform retention, original frame timestamps, audio, and metadata remux
- HEVC encoder validation before 8K is exposed
- 30-second segmented 8K/long-quality jobs, atomic checkpoints, compatible resume, and segment assembly
- Storage preflight, cancellation cleanup, critical-thermal pause, finite iOS background cleanup, idle-timer control, persistent history, pause/resume UI, Photos save, Files/share, and diagnostic JSON
- Privacy manifest, no networking code, no analytics, no accounts, no server processing, and no third-party dependencies
- Simulator unit tests plus unsigned iphoneos/arm64 IPA structure validation in CI

## Truth boundary

CI proves compilation, simulator tests, iPhoneOS targeting, arm64 Mach-O output, bundle metadata, and IPA structure. It cannot prove Apple model execution, tile quality, memory/thermal behavior, audio sync, or 8K playback on a physical iPhone.

HDR preservation is deliberately blocked in the current AI path because it has not yet been verified end-to-end as 10-bit. HDR sources can be explicitly converted to tagged Rec.709 SDR; the app never silently claims that an 8-bit result preserved HDR.

A release candidate still requires the physical-device acceptance matrix in `DEVICE_TESTING.md`. Until those checks pass, this repository is a buildable device candidate, not a device-validated release.

## Build

Open `ClarityVideo.xcodeproj` in Xcode 26, select the ClarityVideo scheme and an iOS 26 device, then build. The bundle identifier is `com.nightvibes33.clarityvideo`.

GitHub Actions publishes:

- `ClarityVideo-unsigned.ipa`
- `ClarityVideo-unsigned.ipa.sha256`
- `build-metadata.json`
- `xcodebuild.log`

The IPA is unsigned and must be signed before stock iOS will install it.
