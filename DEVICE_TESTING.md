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
- [ ] HDR Preserve is blocked; explicit SDR conversion reports Rec.709 output.
- [ ] Airplane-mode processing succeeds and packet capture shows no source/network transfer.

## Artifact evidence to retain

Keep the commit SHA, Actions run URL, IPA SHA-256, device model, iOS build, diagnostic JSON, source/output metadata, peak memory, thermal transitions, frame-processing FPS, and short before/after crops for every accepted route.
