# avif_native

Pure Dart AVIF encoding and decoding through FFI and Dart native-assets hooks. Consumers do not install libavif, codecs, CMake, or a compiler.

For Flutter widgets and image providers, use [`flutter_avif_native`](https://github.com/Zhangw1998/flutter_avif_native).

## Build configuration

Configuration belongs in the application or workspace root `pubspec.yaml`:

```yaml
hooks:
  user_defines:
    avif_native:
      features: full       # decode, encode, full, or auto
      decoder: dav1d       # aom or dav1d
      encoder: aom         # aom
```

Available initial profiles:

```text
decode + dav1d
encode + aom
full + aom + aom
full + dav1d + aom
```

`auto` currently uses the selected full profile. A future link hook can infer used FFI symbols.

All variants export the same ABI. Check `avifNativeCapabilities`, or let unsupported encode/decode calls throw `UnsupportedError` with configuration instructions.

## API

```dart
import 'dart:io';
import 'package:avif_native/avif_native.dart';

void main() {
  final image = decodeAvif(File('image.avif').readAsBytesSync());
  final encoded = encodeAvifFrames(
    width: image.width,
    height: image.height,
    frames: [
      for (final frame in image.frames)
        AvifEncodeFrame(rgba: frame.rgba, duration: frame.duration),
    ],
  );
  File('output.avif').writeAsBytesSync(encoded);
}
```

Supports still and animated AVIF, alpha, EXIF bytes, quantizers, codec speed, threads, timescale, and repetition count.

Native sources are pinned in `native/versions.json`; third-party licenses are in `LICENSES/`.
