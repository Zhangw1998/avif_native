#!/bin/sh
set -eu
root="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
exec "$root/native/build_unix.sh" macos-arm64 "${1:-full-aom-aom}"
