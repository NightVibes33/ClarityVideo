# ClarityVideo — App Store release gate

The public App Store build is the normal Release target. The recovered third-party neural-model build is experimental and is intentionally excluded from the App Store candidate.

## Automated release gates

- Build with Xcode 26+ and the iOS 26 SDK.
- Bundle ID: `com.nightvibes33.clarityvideo`.
- Minimum OS: iOS 26.
- iPhone-only, portrait UI.
- Opaque 1024×1024 app icon.
- Privacy manifest bundled and valid.
- Required-reason declarations for disk space, file timestamp metadata, and app-local UserDefaults.
- No networking/analytics APIs in the app target.
- No simulator visual-QA fixtures in the device binary.
- No `DLSSNeuralHead128` model asset in the public build.
- Core tests, simulator media matrix, Release iphoneos build, and visual snapshot workflow all green.

## Physical-device acceptance before submission

Run `DEVICE_TESTING.md` against the exact commit you intend to upload. Keep the diagnostic JSON and output evidence.

At minimum verify:
- fresh install and cold launch
- Photos, Files, and Camera import
- 720p → 4K and 1080p → 4K
- portrait orientation retention
- five-minute audio/video sync
- cancellation removes incomplete output
- storage preflight matches real working-space use
- repeated preview/settings changes do not grow cache without bound
- thermal pause/resume
- 8K is hidden when unsupported; when exposed, a real 8K export reopens successfully
- airplane-mode processing works without upload/network traffic

## App Store Connect

Current Apple upload minimum (September 2026) is Xcode 26+ with the iOS 26 SDK or later.

Use product-page claims that match the public binary only:
- private, on-device video enhancement
- Apple Super Resolution on supported devices
- 4K export
- up to 8K on devices that pass the hardware probe
- no account
- no cloud upload

Do not advertise or screenshot the experimental recovered neural/DLSS build in the App Store version unless you have explicit rights to distribute the model weights and use the relevant trademarks.

Recommended category: **Photo & Video**.

Before review, complete:
- Privacy Nutrition Label
- updated age-rating questionnaire
- Accessibility Nutrition Label using only verified supported features
- privacy-policy URL
- support URL
- 1–10 real app screenshots with no alpha/transparency
- specific Notes for Review describing capability-gated 8K and on-device processing

## Review note draft

ClarityVideo enhances user-selected videos entirely on-device and does not require an account. Reviewers can import a short video from Photos or Files, choose 4K, and continue to Export. Apple Super Resolution availability is detected on-device. 8K controls appear only on hardware that passes the encoder capability probe. Camera and microphone permissions are requested only when Camera import is chosen. No user video is uploaded by the app.
