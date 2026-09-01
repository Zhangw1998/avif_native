#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: $0 <target> <profile>" >&2
  exit 2
fi

target=$1
profile=$2
root=$(cd "$(dirname "$0")/../.." && pwd)
repo=$(cd "$root/../.." && pwd)
cache=${AVIF_NATIVE_CACHE:-"$repo/.native-cache"}
sources="$cache/sources"
build="$cache/build/$target/$profile"
dist="$repo/dist/$target/$profile"
versions="$root/native/versions.json"

for tool in git cmake ninja python3; do
  command -v "$tool" >/dev/null || { echo "missing build tool: $tool" >&2; exit 1; }
done

json_value() {
  python3 - "$versions" "$1" "$2" <<'PY'
import json, sys
with open(sys.argv[1], encoding='utf-8') as f:
    print(json.load(f)[sys.argv[2]][sys.argv[3]])
PY
}

checkout() {
  local name=$1 url commit dir
  url=$(json_value "$name" repository)
  commit=$(json_value "$name" commit)
  dir="$sources/$name"
  if [[ -d "$dir/.git" ]] && [[ "$(git -C "$dir" rev-parse HEAD 2>/dev/null || true)" == "$commit" ]]; then
    return
  fi
  rm -rf "$dir"
  git clone --quiet --filter=blob:none --no-checkout "$url" "$dir"
  git -C "$dir" fetch --quiet --depth 1 origin "$commit"
  git -C "$dir" checkout --quiet --detach "$commit"
}

mkdir -p "$sources" "$dist"
checkout libavif
checkout libaom
checkout dav1d
rm -rf "$sources/libavif/ext/aom" "$sources/libavif/ext/dav1d"
ln -s "$sources/libaom" "$sources/libavif/ext/aom"
ln -s "$sources/dav1d" "$sources/libavif/ext/dav1d"
python3 - "$sources/libavif/cmake/Modules/LocalDav1d.cmake" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text()
marker = "if(AVIF_NATIVE_DAV1D_CROSS_FILE)"
if marker not in text:
    text = text.replace(
        "    if(CROSS_FILE)\n        set(EXTRA_ARGS",
        "    if(AVIF_NATIVE_DAV1D_CROSS_FILE)\n"
        "        set(CROSS_FILE \"${AVIF_NATIVE_DAV1D_CROSS_FILE}\")\n"
        "    endif()\n\n"
        "    if(CROSS_FILE)\n        set(EXTRA_ARGS",
    )
    path.write_text(text)
PY

cmake_args=(
  -S "$root/native"
  -B "$build"
  -G Ninja
  -DCMAKE_BUILD_TYPE=MinSizeRel
  -DLIBAVIF_SOURCE_DIR="$sources/libavif"
  -DAVIF_PROFILE="$profile"
)

set_apple_cross_file() {
  local sdk=$1 system=$2 cpu=$3 arch=$4 minimum=$5
  local sdk_path cross_file
  sdk_path=$(xcrun --sdk "$sdk" --show-sdk-path)
  cross_file="$cache/cross/$target.meson"
  mkdir -p "$(dirname "$cross_file")"
  cat > "$cross_file" <<EOF
[binaries]
c = ['clang']
cpp = ['clang++']
ar = ['ar']
strip = ['strip']
pkg-config = ['pkg-config']

[host_machine]
system = '$system'
cpu_family = '$cpu'
cpu = '$cpu'
endian = 'little'

[built-in options]
c_args = ['-arch', '$arch', '-isysroot', '$sdk_path', '$minimum']
c_link_args = ['-arch', '$arch', '-isysroot', '$sdk_path', '$minimum']
EOF
  cmake_args+=( -DAVIF_NATIVE_DAV1D_CROSS_FILE="$cross_file" )
}

ext=
case "$target" in
  macos-arm64)
    set_apple_cross_file macosx darwin aarch64 arm64 -mmacosx-version-min=12.0
    cmake_args+=( -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=12.0 )
    ext=dylib
    ;;
  macos-x64)
    set_apple_cross_file macosx darwin x86_64 x86_64 -mmacosx-version-min=12.0
    cmake_args+=( -DCMAKE_OSX_ARCHITECTURES=x86_64 -DCMAKE_OSX_DEPLOYMENT_TARGET=12.0 -DAOM_TARGET_CPU=x86_64 )
    ext=dylib
    ;;
  ios-device-arm64)
    set_apple_cross_file iphoneos ios aarch64 arm64 -miphoneos-version-min=13.0
    cmake_args+=( -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_SYSROOT=iphoneos -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=13.0 )
    ext=dylib
    ;;
  ios-simulator-arm64)
    set_apple_cross_file iphonesimulator ios aarch64 arm64 -mios-simulator-version-min=13.0
    cmake_args+=( -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_SYSROOT=iphonesimulator -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=13.0 )
    ext=dylib
    ;;
  ios-simulator-x64)
    set_apple_cross_file iphonesimulator ios x86_64 x86_64 -mios-simulator-version-min=13.0
    cmake_args+=( -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_SYSROOT=iphonesimulator -DCMAKE_OSX_ARCHITECTURES=x86_64 -DCMAKE_OSX_DEPLOYMENT_TARGET=13.0 )
    ext=dylib
    ;;
  android-arm64|android-arm|android-x64)
    ndk=${ANDROID_NDK_HOME:-${ANDROID_NDK_ROOT:-${ANDROID_NDK_LATEST_HOME:-}}}
    [[ -n "$ndk" ]] || { echo "set ANDROID_NDK_HOME" >&2; exit 1; }
    case "$target" in
      android-arm64) abi=arm64-v8a ;;
      android-arm) abi=armeabi-v7a ;;
      android-x64) abi=x86_64 ;;
    esac
    cmake_args+=(
      -DCMAKE_TOOLCHAIN_FILE="$ndk/build/cmake/android.toolchain.cmake"
      -DANDROID_ABI="$abi"
      -DANDROID_PLATFORM=21
    )
    ext=so
    ;;
  linux-x64)
    cmake_args+=( -DCMAKE_SYSTEM_PROCESSOR=x86_64 )
    ext=so
    ;;
  linux-arm64)
    if [[ "$(uname -m)" != "aarch64" && "$(uname -m)" != "arm64" ]]; then
      command -v aarch64-linux-gnu-gcc >/dev/null || {
        echo "install gcc-aarch64-linux-gnu for linux-arm64" >&2
        exit 1
      }
      cmake_args+=(
        -DCMAKE_SYSTEM_NAME=Linux
        -DCMAKE_SYSTEM_PROCESSOR=aarch64
        -DCMAKE_C_COMPILER=aarch64-linux-gnu-gcc
      )
    fi
    ext=so
    ;;
  *)
    echo "unsupported target: $target" >&2
    exit 2
    ;;
esac

rm -rf "$build"
cmake "${cmake_args[@]}"
cmake --build "$build" --target avif_native --parallel

library=$(find "$build" -type f -name "libavif_native.$ext" -print -quit)
[[ -n "$library" ]] || { echo "built library not found" >&2; exit 1; }
cp "$library" "$dist/libavif_native.$ext"
case "$target" in
  macos-*|ios-*) strip -x "$dist/libavif_native.$ext" ;;
  android-*)
    llvm_strip=$(find "$ndk/toolchains/llvm/prebuilt" -path '*/bin/llvm-strip' -print -quit)
    "$llvm_strip" --strip-unneeded "$dist/libavif_native.$ext"
    ;;
  linux-*) strip --strip-unneeded "$dist/libavif_native.$ext" ;;
esac
gzip -9 -c "$dist/libavif_native.$ext" > "$dist/libavif_native.$ext.gz"

echo "$dist/libavif_native.$ext"
