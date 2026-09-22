# Media executables and reproducible acquisition

JDAD Recorder launches FFmpeg and ffprobe as separate local processes. The Windows installer includes only `vendor/win32-x64/`. The macOS ARM64 executables are local development/test tools, built with `--enable-nonfree`, and must not be redistributed.

## Locked binary provenance

Distributor release: [eugeneware/ffmpeg-static b6.1.1](https://github.com/eugeneware/ffmpeg-static/releases/tag/b6.1.1). This is a third-party distributor, not an official FFmpeg binary release. Its [pinned acquisition recipe](https://github.com/eugeneware/ffmpeg-static/blob/b6.1.1/download-binaries/index.sh) identifies the binary providers.

- Windows x64: Gyan `6.1.1-essentials_build-www.gyan.dev`, GPL v3; source FFmpeg revision [`e38092ef93`](https://github.com/FFmpeg/FFmpeg/commit/e38092ef93). Both ffmpeg.exe and ffprobe.exe come from the same release. The exact upstream README, including configuration and external-library versions, and GPL v3 LICENSE are included next to the executables.
- Development macOS ARM64: OSXExperts FFmpeg 6.0, including `--enable-nonfree` as reported by the actual binary. Release asset naming does not imply that every platform binary has the release tag's version. This tool is excluded from the Windows package.

`npm run media:fetch` fetches compressed release assets from the npmmirror mirror and checks **both compressed and decompressed SHA-256 digests against the values published by the upstream GitHub release**, before installing anything. Digests were obtained from [GitHub's release-asset metadata](https://github.com/eugeneware/ffmpeg-static/releases/expanded_assets/b6.1.1), independently of npmmirror, and are locked in the fetch script. Staged bytes are verified, made executable, then renamed into place. Correct existing files are reused. No provider npm install scripts are run.

The fetcher uses system curl (available on Windows 11 and macOS) and built-in Node gzip decoding. Set `MEDIA_DOWNLOAD_BASE=https://github.com/eugeneware/ffmpeg-static/releases/download/b6.1.1` to download directly from upstream; the same locked checksums apply. `node scripts/fetch-media.mjs win32-x64` fetches only the shipping platform.

| Asset | SHA-256 (uncompressed upstream digest) |
|---|---|
| ffmpeg-win32-x64 | `04e1307997530f9cf2fe35cba2ca7e8875ca91da02f89d6c7243df819c94ad00` |
| ffprobe-win32-x64 | `3a7e2dc003dc2cd1472827e4c7c4f056ae1ae0ae7c5bbc580c99b49827351ba4` |
| ffmpeg-darwin-arm64 | `a90e3db6a3fd35f6074b013f948b1aa45b31c6375489d39e572bea3f18336584` |
| ffprobe-darwin-arm64 | `bb2db6f5d8cef919da12fbf592119a987202a8c060a886f3cab091f9cab90b64` |

## License and corresponding source

The Windows binaries are GPL v3 FFmpeg builds including libx264; they are not LGPL-only builds. The included LICENSE contains the complete GPL v3 text. FFmpeg and its dependencies retain their copyrights. This software is based in part on the work of the Independent JPEG Group; JDAD has not modified those sources.

The matching FFmpeg revision is linked above. The [Gyan build repository](https://github.com/GyanD/codexffmpeg/tree/6.1.1) provides the release context. The included upstream README records all external-library versions, including x264 v0.164.3172, and the build configuration; retain these records when reproducing the build. The FFmpeg source tag alone does not cover the external libraries.

Before distributing this local team preview more broadly, provide recipients the complete corresponding source for these exact GPL binaries, including dependency sources and build scripts, using a distribution method permitted by the GPL. Merely linking to the FFmpeg homepage is insufficient. This repository records provenance, hashes and license texts; it does not claim to contain a complete corresponding-source bundle.

## Export resources and validation

Selected clips are normalized sequentially to temporary lossless FFV1/PCM files; a concat manifest feeds the final encoder. This preserves reordered audio and prevents decoder queues from retaining an entire source in memory. Intermediates require additional disk space. Frame camera commands are written incrementally to a file and drive crop plus scale reconfiguration. GIF uses per-frame palettes, avoiding whole-video palette buffering. Cancellation terminates the active child and removes only that export's temporary directory; existing output is replaced only after successful encoding.

Actual macOS integration tests generate and decode fixtures to verify reordered video/audio, rotated-input dimensions, camera crop, multi-frame GIF, seekable WebM remux, successful replacement, cancellation preservation, and temporary cleanup. Both Windows executables have validated PE signatures and AMD64 machine types. Windows executable runtime/capture/installer operation still requires Windows testing; PE inspection is not a runtime test.
