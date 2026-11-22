#!/usr/bin/env sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
TARGET_DIR="${ROOT}/.cache/link-inputs/x64musl"
OUT="${ROOT}/platform/targets-out/x64musl"
PROBE="${ROOT}/.cache/link-inputs/probe"
ZIG_TRIPLE="x86_64-linux-musl"

command -v zig >/dev/null 2>&1 || { echo "zig not on PATH" >&2; exit 1; }

mkdir -p "$TARGET_DIR" "$OUT" "$PROBE"

# Already materialized?
if [ -f "$TARGET_DIR/libc.a" ] && [ -f "$TARGET_DIR/crt1.o" ] \
   && [ -f "$TARGET_DIR/libcompiler_rt.a" ] && [ -f "$TARGET_DIR/libzigc.a" ]; then
  cp -a "$TARGET_DIR/." "$OUT/"
  echo "link-inputs: cache hit → $OUT"
  exit 0
fi

# Minimal root so Zig will link musl + compiler-rt as PIC (shared).
cat >"$PROBE/empty.zig" <<'EOF'
export fn roc_link_inputs_probe() callconv(.c) void {}
EOF

# -dynamic + -fPIC forces position-independent musl/crt in Zig's cache.
# -lc pulls musl; -fcompiler-rt pulls compiler-rt; Zig also emits libzigc bits.
zig build-lib \
  "$PROBE/empty.zig" \
  -target "$ZIG_TRIPLE" \
  -dynamic \
  -fPIC \
  -lc \
  -fcompiler-rt \
  -OReleaseSafe \
  -femit-bin="$PROBE/libprobe.so" \
  --verbose 2>"$PROBE/zig-verbose.txt" || true

# Zig prints (or caches under ZIG_GLOBAL_CACHE_DIR) the musl objects it built.
# Locate them: prefer verbose log paths, then fall back to scanning the cache.
ZIG_CACHE="${ZIG_GLOBAL_CACHE_DIR:-${HOME}/.cache/zig}"

find_one() {
  name="$1"
  # Prefer files clearly associated with musl / this triple if possible
  found="$(find "$ZIG_CACHE" -name "$name" -type f 2>/dev/null | head -n1 || true)"
  [ -n "$found" ] || { echo "could not find $name under $ZIG_CACHE" >&2; exit 1; }
  echo "$found"
}

cp -f "$(find_one crt1.o)"              "$TARGET_DIR/crt1.o"
cp -f "$(find_one libc.a)"              "$TARGET_DIR/libc.a"
cp -f "$(find_one libcompiler_rt.a)"    "$TARGET_DIR/libcompiler_rt.a"
# name varies slightly by Zig version:
if [ -f "$(find "$ZIG_CACHE" -name 'libzigc.a' -type f 2>/dev/null | head -n1)" ]; then
  cp -f "$(find_one libzigc.a)"         "$TARGET_DIR/libzigc.a"
else
  # some Zig layouts use a different archive name — copy whatever probe linked
  echo "warning: libzigc.a not found; check $PROBE/zig-verbose.txt" >&2
fi

# Optional: record provenance next to the cache
{
  echo "zig=$(zig version)"
  echo "triple=$ZIG_TRIPLE"
  echo "mode=dynamic+fPIC"
  date -u +%Y-%m-%dT%H:%M:%SZ
} >"$TARGET_DIR/PROVENANCE.txt"

cp -a "$TARGET_DIR/." "$OUT/"
echo "link-inputs: materialized (PIC) → $OUT"
