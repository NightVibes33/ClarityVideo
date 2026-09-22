# ClarityVideo Support

ClarityVideo is an on-device iPhone video enhancement app.

## Before requesting support

If an export cannot start, check:
- available iPhone storage
- whether the selected output resolution is available on the device
- whether Apple Super Resolution is available in **Settings → Video engine diagnostics**
- whether the device is thermally constrained

For large or long videos, try a short 4K export first.

## Diagnostics

Open **Settings → Video engine diagnostics**. The diagnostics screen can:
- run capability probes
- test Apple Super Resolution
- test 4K and supported 8K encoding
- clear temporary processing cache
- prepare diagnostic JSON

When reporting a processing problem, include the diagnostic JSON when possible. Do not upload a private source video unless you intentionally want to share it.

## Contact and bug reports

Open an issue in this repository and include:
- ClarityVideo version and build
- iPhone model
- iOS version
- source resolution, duration, codec, and HDR/SDR status
- selected output resolution and quality preset
- the exact error shown by the app
- diagnostic JSON when available

Repository issues: https://github.com/NightVibes33/ClarityVideo/issues
