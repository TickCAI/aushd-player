#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$root"
if [ "${SKIP_BUILD:-0}" != "1" ]; then
  flutter build linux --release
fi

out="$root/build/linux/package"
stage="$out/aushd-player"
rm -rf "$out"
mkdir -p "$stage"
cp -r build/linux/x64/release/bundle/. "$stage/"
cp linux/packaging/cloud.zerk.play.desktop linux/packaging/cloud.zerk.play.png "$stage/"
tar -C "$out" -czf "$out/AusHD-Player-Linux-x64.tar.gz" aushd-player
sha256sum "$out/AusHD-Player-Linux-x64.tar.gz"
