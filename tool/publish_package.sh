#!/usr/bin/env bash
set -euo pipefail

package=${1:-}
mode=${2:---dry-run}
case "$package" in
  avif_native) publisher=(dart pub publish) ;;
  flutter_avif_native) publisher=(flutter pub publish) ;;
  *) echo "usage: $0 <avif_native|flutter_avif_native> [--dry-run|--publish|--force]" >&2; exit 64 ;;
esac
case "$mode" in
  --dry-run) publish_args=(--dry-run) ;;
  --publish) publish_args=() ;;
  --force) publish_args=(--force) ;;
  *) echo "unsupported mode: $mode" >&2; exit 64 ;;
esac

root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"
stage=$(dart run tool/prepare_publish.dart "$package")
trap 'rm -rf "$stage"' EXIT
cd "$stage"
"${publisher[@]}" "${publish_args[@]}"
