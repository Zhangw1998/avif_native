# Native release

## Profiles

| Profile | Decoder | Encoder |
| --- | --- | --- |
| `decode-dav1d` | dav1d | — |
| `encode-aom` | — | libaom |
| `full-aom-aom` | libaom | libaom |
| `full-dav1d-aom` | dav1d | libaom |

Source commits are pinned in `native/versions.json`.

## Local development

Local builds are for reproduction and smoke testing only:

```sh
tool/native/build_unix.sh macos-arm64 full-aom-aom
```

The dav1d profiles require Meson. AOM x64 builds require NASM.

## GitHub release

1. Push the repository to GitHub.
2. Push a tag such as `native-v0.1.0`, or run the `Native release` workflow manually.
3. The workflow builds every target/profile, verifies dependencies, creates gzip archives and publishes `manifest.json` with SHA-256 hashes.
4. Copy the generated manifest into `native/manifest.json`.
5. Remove `native/artifacts/`, run the integration checks, then publish the Dart package.

The checked-in macOS arm64 artifact is a development bootstrap. Published versions must use only immutable GitHub Release URLs and checksums.
