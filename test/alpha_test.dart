import 'dart:io';

import 'package:avif_native/avif_native.dart';
import 'package:test/test.dart';

void main() {
  final bytes = File('test/fixtures/test_alpha.avif').readAsBytesSync();

  test('decode keeps straight alpha by default', () {
    final rgba = decodeAvif(bytes).frames.single.rgba;

    var transparentColoured = 0;
    for (var i = 0; i < rgba.length; i += 4) {
      if (rgba[i + 3] == 0 &&
          (rgba[i] != 0 || rgba[i + 1] != 0 || rgba[i + 2] != 0)) {
        ++transparentColoured;
      }
    }
    expect(transparentColoured, greaterThan(0));
  });

  test('premultiplyAlpha premultiplies decoded frames', () {
    final straight = decodeAvif(bytes);
    final premultiplied = decodeAvif(bytes, premultiplyAlpha: true);
    final rgba = straight.frames.single.rgba;
    final premultipliedRgba = premultiplied.frames.single.rgba;
    expect(premultipliedRgba, hasLength(rgba.length));

    int offset(int x, int y) => (y * straight.width + x) * 4;

    // Fixture quadrants: transparent white, 50% white, transparent red,
    // 50% red.
    expect(rgba[offset(2, 2) + 3], 0);
    expect(rgba[offset(2, 2)], greaterThan(200));
    expect(premultipliedRgba[offset(2, 2)], 0);
    expect(premultipliedRgba[offset(2, 2) + 1], 0);
    expect(premultipliedRgba[offset(2, 2) + 2], 0);
    expect(premultipliedRgba[offset(12, 2) + 3], inInclusiveRange(100, 160));
    expect(premultipliedRgba[offset(12, 2)], inInclusiveRange(110, 145));

    var zeroed = 0;
    var scaled = 0;
    for (var i = 0; i < rgba.length; i += 4) {
      final alpha = rgba[i + 3];
      expect(premultipliedRgba[i + 3], alpha);
      if (alpha == 0) {
        expect(premultipliedRgba[i], 0);
        expect(premultipliedRgba[i + 1], 0);
        expect(premultipliedRgba[i + 2], 0);
        ++zeroed;
      } else if (alpha == 255) {
        expect(premultipliedRgba[i], rgba[i]);
        expect(premultipliedRgba[i + 1], rgba[i + 1]);
        expect(premultipliedRgba[i + 2], rgba[i + 2]);
      } else {
        expect(premultipliedRgba[i], lessThanOrEqualTo(rgba[i]));
        expect(premultipliedRgba[i + 1], lessThanOrEqualTo(rgba[i + 1]));
        expect(premultipliedRgba[i + 2], lessThanOrEqualTo(rgba[i + 2]));
        ++scaled;
      }
    }
    expect(zeroed, greaterThan(0));
    expect(scaled, greaterThan(0));
  });

  test('AvifDecoder.getNextFrame honours premultiplyAlpha', () {
    final decoder = AvifDecoder(bytes, premultiplyAlpha: true);
    try {
      expect(decoder.premultiplyAlpha, isTrue);
      final rgba = decoder.getNextFrame().rgba;
      for (var i = 0; i < rgba.length; i += 4) {
        if (rgba[i + 3] != 0) continue;
        expect(rgba[i], 0);
        expect(rgba[i + 1], 0);
        expect(rgba[i + 2], 0);
      }
    } finally {
      decoder.dispose();
    }
  });
}
