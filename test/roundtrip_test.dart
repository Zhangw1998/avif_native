import 'dart:io';

import 'package:avif_native/avif_native.dart';
import 'package:test/test.dart';

void main() {
  test('static AVIF decode, encode, and decode round trip', () {
    expect(avifNativeCapabilities.canDecode, isTrue);
    expect(avifNativeCapabilities.canEncode, isTrue);

    final source = decodeAvif(
      File('test/fixtures/test_static.avif').readAsBytesSync(),
    );
    final encoded = encodeAvifFrames(
      width: source.width,
      height: source.height,
      frames: [
        for (final frame in source.frames)
          AvifEncodeFrame(rgba: frame.rgba, duration: frame.duration),
      ],
    );
    final result = decodeAvif(encoded);

    expect(result.width, source.width);
    expect(result.height, source.height);
    expect(result.frames, hasLength(source.frames.length));
  });
}
