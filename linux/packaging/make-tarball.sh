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

# The Dart FFI loads 'libmpv.so.2' by name at play time. A tar.gz containing
# only the Flutter bundle starts fine but cannot decode anything on a machine
# without a system-wide libmpv, so vendor the library and its private
# dependency chain and launch through a script that points dlopen at them.
stage_lib="$stage/lib"
mkdir -p "$stage_lib"
mpv=""
for cand in \
  /usr/lib/x86_64-linux-gnu/libmpv.so.2 \
  /usr/lib/libmpv.so.2 \
  /lib/x86_64-linux-gnu/libmpv.so.2; do
  if [ -f "$cand" ]; then mpv="$cand"; break; fi
done

if [ -n "$mpv" ]; then
  cp -L "$mpv" "$stage_lib/libmpv.so.2"
  ldd "$mpv" | awk '/=> \// {print $3}' | while read -r dep; do
    case "$(basename "$dep")" in
      libc.so.*|libm.so.*|libdl.so.*|libpthread.so.*|librt.so.*|ld-linux*|libstdc++.so.*|libgcc_s.so.*) continue ;;
    esac
    cp -n -L "$dep" "$stage_lib/" 2>/dev/null || true
  done
  echo "bundled $(find "$stage_lib" -name '*.so*' | wc -l) shared libraries (including libmpv.so.2)"
else
  echo "::warning::libmpv.so.2 not found on this build host; the Linux package still needs a system libmpv"
fi

# Always ship the launcher, even when the build host lacked libmpv, so the
# desktop entry and the documented start command stay the same.
cat > "$stage/aushd-player" <<'LAUNCH'
#!/usr/bin/env bash
here="$(cd "$(dirname "$0")" && pwd)"
export LD_LIBRARY_PATH="$here/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
exec "$here/zerk_play" "$@"
LAUNCH
chmod +x "$stage/aushd-player"

tar -C "$out" -czf "$out/AusHD-Player-Linux-x64.tar.gz" aushd-player
sha256sum "$out/AusHD-Player-Linux-x64.tar.gz"
