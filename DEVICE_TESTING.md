# Physical-device acceptance

CI cannot execute Apple's on-device models. Do not call a commit release-ready until these checks pass on a compatible iPhone running iOS 26.

## Setup

1. Download the latest `ClarityVideo-unsigned-ipa` Actions artifact.
2. Sign `ClarityVideo-unsigned.ipa` with a valid development or distribution identity and entitlements.
3. Install it on the test iPhone and open Diagnostics.
4. Export the diagnostic JSON before and after the media tests.

## Required checks

- [ ] App installs and launches without a pre-main crash.
- [ ] Full-quality or low-latency SR reports supported.
- [ ] Model readiness/download completes and the 1280x720 one-frame self-test passes.
- [ ] Export the enhanced one-frame PNG and retain it with the diagnostic JSON.
- [ ] Run and export the built-in five-second 4K diagnostic video.
- [ ] A 720p clip exports to exactly 3840x2160 and reopens.
- [ ] A 1080p clip exports to exactly 3840x2160 and reopens.
- [ ] A portrait 1080p clip exports as 2160x3840 with correct orientation.
- [ ] Audio sync is checked near the beginning, middle, and end of a five-minute clip.
- [ ] A hard scene cut does not carry denoise/SR history into the next shot.
- [ ] Tile seams are absent in slow pans, skies, gradients, foliage, hair, and fine text.
- [ ] Cancel removes incomplete final output.
- [ ] Pause during segmented 8K work, relaunch, resume, and finish successfully.
- [ ] Critical thermal state pauses safely and resumes without corrupting the checkpoint.
- [ ] 8K is hidden if the encoder probe fails.
- [ ] If the probe passes, 1080p and 4K sources export to exactly 7680x4320 and reopen.
- [ ] Run and export the built-in five-second 8K diagnostic video.
- [ ] HDR Preserve is blocked; explicit SDR conversion reports Rec.709 output.
- [ ] HDR-to-SDR highlights, skin tones, and saturation are visually checked against the source on a calibrated display.
- [ ] Airplane-mode processing succeeds and packet capture shows no source/network transfer.

## Artifact evidence to retain

Keep the commit SHA, Actions run URL, IPA SHA-256, device model, iOS build, diagnostic JSON, source/output metadata, peak memory, thermal transitions, frame-processing FPS, and short before/after crops for every accepted route.

## Required media matrix

Run five-to-ten-second, legally distributable clips covering 480p animation, 720p faces, 720p gaming, 1080p daylight, 1080p low-light noise, and 4K high motion. Record input/output dimensions, codecs, frame count, durations, processing time/FPS, peak memory, thermal state, output size, A/V drift, processor revision, AI scale, and final-resize scale for each.

## Quality comparison

For representative clips, retain matched crops from AVFoundation resize, Apple low-latency SR, Apple full-quality SR, and a licensed Topaz Video AI reference. Review texture, faces, hair, text, halos, noise, compression blocks, shimmer, ghosting, color accuracy, and frame consistency. Do not claim universal Topaz equivalence.
