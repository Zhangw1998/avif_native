#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT

case "$(uname -s)-$(uname -m)" in
  Darwin-arm64) target=macos-arm64; library=libavif_native.dylib ;;
  Darwin-x86_64) target=macos-x64; library=libavif_native.dylib ;;
  Linux-aarch64) target=linux-arm64; library=libavif_native.so ;;
  Linux-x86_64) target=linux-x64; library=libavif_native.so ;;
  *) echo "unsupported profile-test host: $(uname -s)-$(uname -m)" >&2; exit 2 ;;
esac

check_profile() {
  local name=$1 features=$2 decoder=$3 encoder=$4 profile=$5 can_decode=$6 can_encode=$7
  local app="$temporary/$name"
  mkdir -p "$app/bin" "$app/test"
  cp "$root/test/fixtures/test_static.avif" "$app/test/"
  {
    cat <<EOF
name: profile_${name//-/_}
environment:
  sdk: ^3.10.0
dependencies:
  avif_native:
    path: $root
hooks:
  user_defines:
    avif_native:
      features: $features
EOF
    [[ -z "$decoder" ]] || echo "      decoder: $decoder"
    [[ -z "$encoder" ]] || echo "      encoder: $encoder"
  } > "$app/pubspec.yaml"

  cat > "$app/bin/main.dart" <<EOF
import 'dart:io';
import 'dart:typed_data';
import 'package:avif_native/avif_native.dart';

void main() {
  if (avifNativeCapabilities.canDecode != $can_decode ||
      avifNativeCapabilities.canEncode != $can_encode) {
    throw StateError('unexpected native capabilities');
  }
  if ($can_decode) {
    if (decodeAvif(File('test/test_static.avif').readAsBytesSync()).frames.isEmpty) {
      throw StateError('decode returned no frames');
    }
  } else {
    try {
      decodeAvif(Uint8List(1));
      throw StateError('decode unexpectedly succeeded');
    } on UnsupportedError { /* expected */ }
  }
  if ($can_encode) {
    final output = encodeAvifFrames(
      width: 1,
      height: 1,
      frames: [AvifEncodeFrame(rgba: Uint8List.fromList([255, 0, 0, 255]))],
    );
    if (output.isEmpty) throw StateError('encode returned no data');
  } else {
    try {
      encodeAvifFrames(
        width: 1,
        height: 1,
        frames: [AvifEncodeFrame(rgba: Uint8List(4))],
      );
      throw StateError('encode unexpectedly succeeded');
    } on UnsupportedError { /* expected */ }
  }
}
EOF

  (cd "$app" && dart pub get >/dev/null && dart run bin/main.dart >/dev/null)
  local expected actual
  expected=$(python3 - "$root/native/manifest.json" "$target-$profile" <<'PY'
import json, sys
print(json.load(open(sys.argv[1]))['artifacts'][sys.argv[2]]['librarySha256'])
PY
)
  actual=$(find "$app/.dart_tool/hooks_runner" -type f -name "$library" -exec shasum -a 256 {} \; |
    awk -v expected="$expected" '$1 == expected { print $1; exit }')
  [[ "$actual" == "$expected" ]] || { echo "$name selected the wrong artifact" >&2; exit 1; }
  echo "$name -> $profile: OK"
}

check_profile decode-default decode '' '' decode-dav1d true false
check_profile encode-default encode '' '' encode-aom false true
check_profile full-default full '' '' full-aom-aom true true
check_profile full-dav1d full dav1d aom full-dav1d-aom true true
