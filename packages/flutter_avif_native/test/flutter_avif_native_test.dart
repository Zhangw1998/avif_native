import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:flutter_avif_native/flutter_avif_native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('memory provider key is stable for the same byte buffer', () async {
    final bytes = Uint8List(4);
    final provider = AvifMemoryImage(bytes);

    expect(
      await provider.obtainKey(ImageConfiguration.empty),
      AvifMemoryImage(bytes),
    );
  });
}
