# Recovered neural renderer: iOS conversion

`convert_model_for_ios.py` uses the recovered transformer graph from
[DLSSMac](https://github.com/Mappsnet7/DLSSMac) at commit
`f47a05b7f11e2d02c43bfa5337984fe2cee546f2` and the matching, separately
distributed weights from its v0.1.6 release. The weight digest is checked before
conversion. The resulting Core ML graph accepts NCHW float32 `[1,16,128,128]`
features and emits a four-channel neural head. This is *neural rendering at the
input resolution*; the head is not itself a 4K or 8K upscaler.

The manually triggered `ios-neural-model.yml` workflow creates an iOS-targeted
Core ML package as an artifact. Conversion and compilation on a Mac runner do
not establish that the complete graph runs on an iPhone 16: the video feature
preprocessor, temporal history, frame compositor, model loading, tiling and
on-device performance gate still require a validated iOS integration.

The vendored Python reference implementation is Apache 2.0 licensed. Converted
weights retain their original ownership and are kept outside this Git repository.
