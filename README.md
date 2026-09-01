# avif_native

Standalone Dart/Flutter workspace for AVIF support backed by libavif native assets.

- [`packages/avif_native`](packages/avif_native): pure Dart FFI API and configurable build hook.
- [`packages/flutter_avif_native`](packages/flutter_avif_native): Flutter-facing package.

Native release binaries are built by [GitHub Actions](.github/workflows/native-release.yml), not on consumer machines. See [`NATIVE_RELEASE.md`](NATIVE_RELEASE.md) for native builds and [`PUBLISHING.md`](PUBLISHING.md) for pub.dev releases.
