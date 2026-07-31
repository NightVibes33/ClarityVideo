# Clarity Video AI

Clarity Video AI is a native SwiftUI iOS 26 app for private, fully on-device video enhancement and UHD export. It imports from Photos or Files, inspects the real display geometry and media metadata, probes VideoToolbox capabilities, gates 8K behind a hardware encoder test, preserves source audio and timing, and packages a real unsigned arm64 device IPA in GitHub Actions.

## What is implemented

- Photos and security-scoped Files import into a private workspace
- Resolution, orientation, FPS, codec, HDR, duration, and source-size inspection
- Runtime VideoToolbox frame-processor presence checks
- Real 4K, 8K, Main10 hardware-required encoder session probes
- Capability-gated 4K/8K controls and explicit AI/final-resize disclosure
- HEVC export with exact UHD geometry, portrait handling, source frame rate, audio, and metadata
- Storage preflight, cancellation with incomplete-file cleanup, thermal display, history, Photos save, Files/share
- Diagnostics JSON export and physical-device testing boundary
- Privacy manifest and no network/server code or third-party dependencies
- Unit tests plus unsigned iphoneos/arm64 IPA validation in CI

## Important truth boundary

The repository can prove source compilation, tests, iPhoneOS targeting, arm64 Mach-O output, bundle metadata, and IPA structure. Apple frame-processor model download, neural super-resolution quality, real-device memory/thermal behavior, and successful 8K playback require an actual compatible iOS 26 device. The app exposes diagnostics for those checks and does not present CI or simulator results as device proof.

The current production-safe export path uses AVFoundation/VideoToolbox HEVC with exact-size composition. Apple frame-processor APIs are runtime-probed and the UI does not falsely label conventional resizing as neural output. Device-tested SR session integration is tracked in the diagnostics boundary rather than guessed against an unavailable device.

## Build

Open `ClarityVideo.xcodeproj` in Xcode 26, select the ClarityVideo scheme and an iOS 26 device, then build. Bundle identifier: `com.nightvibes33.clarityvideo`.

GitHub Actions publishes:

- `ClarityVideo-unsigned.ipa`
- `ClarityVideo-unsigned.ipa.sha256`
- `build-metadata.json`
- `xcodebuild.log`

The IPA is unsigned and must be signed before stock iOS will install it.
