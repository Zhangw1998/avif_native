import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:avif_native/avif_native.dart';

void main(List<String> args) {
  final input = args.isNotEmpty ? args[0] : 'test/fixtures/test_static.avif';
  final outputDirectory = Directory(
    args.length > 1 ? args[1] : '.dart_tool/avif_native_mvp',
  )..createSync(recursive: true);

  final inputBytes = File(input).readAsBytesSync();
  final decoded = decodeAvif(inputBytes);
  final first = decoded.frames.first;
  assert(first.rgba.length == first.width * first.height * 4);

  final streaming = AvifDecoder(inputBytes);
  try {
    final firstPass = streaming.getNextFrame();
    streaming.reset();
    final replay = streaming.getNextFrame();
    assert(firstPass.rgba.length == replay.rgba.length);
  } finally {
    streaming.dispose();
  }

  final encoded = encodeAvifFrames(
    width: decoded.width,
    height: decoded.height,
    frames: [
      for (final frame in decoded.frames)
        AvifEncodeFrame(rgba: frame.rgba, duration: frame.duration),
    ],
    options: AvifEncodeOptions(repetitionCount: decoded.repetitionCount),
  );
  final roundtrip = decodeAvif(encoded);
  assert(roundtrip.width == decoded.width);
  assert(roundtrip.height == decoded.height);
  assert(roundtrip.frames.length == decoded.frames.length);

  _writePpm(File('${outputDirectory.path}/decoded.ppm'), first);
  File('${outputDirectory.path}/roundtrip.avif').writeAsBytesSync(encoded);
  print(
    '${decoded.width}x${decoded.height}, frames=${decoded.frames.length}, '
    'duration=${decoded.duration.inMilliseconds}ms -> ${outputDirectory.path}',
  );
}

void _writePpm(File output, AvifFrame frame) {
  final rgb = Uint8List(frame.width * frame.height * 3);
  for (var src = 0, dst = 0; src < frame.rgba.length; src += 4) {
    rgb[dst++] = frame.rgba[src];
    rgb[dst++] = frame.rgba[src + 1];
    rgb[dst++] = frame.rgba[src + 2];
  }
  output.writeAsBytesSync([
    ...ascii.encode('P6\n${frame.width} ${frame.height}\n255\n'),
    ...rgb,
  ]);
}
