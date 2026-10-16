#!/usr/bin/env sh
set -eu

#
# 1) Parse the git commit id from: `roc --version` -> "Roc compiler version nightly-2026-10-15-38e6c42"
# 2) Fetch https://raw.githubusercontent.com/roc-lang/roc/${COMMIT}/src/glue/src/ZigGlue.roc
# 3) Write it to .cache/glue/${commit}/ZigGlue.roc
# 4) Run roc glue
#

ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CACHE_DIR="${ROC_GLUE_CACHE:-$ROOT/.cache/glue}"
mkdir -p "$CACHE_DIR"

# --- resolve ZigGlue.roc ---
ZIG_GLUE="${ROC_ZIG_GLUE:-}"

if [ -z "$ZIG_GLUE" ] && [ -f "$ROOT/vendor/glue/ZigGlue.roc" ]; then
  ZIG_GLUE="$ROOT/vendor/glue/ZigGlue.roc"
fi

if [ -z "$ZIG_GLUE" ]; then
  # roc version → "Roc compiler version nightly-2026-10-15-38e6c42"
  VERSION_LINE="$(roc version 2>/dev/null || roc --version 2>/dev/null || true)"
  COMMIT="$(printf '%s\n' "$VERSION_LINE" | sed -n 's/.*nightly-[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}-\([0-9a-f]\{7,40\}\).*/\1/p')"

  if [ -z "$COMMIT" ]; then
    echo "error: could not parse commit from: $VERSION_LINE" >&2
    echo "  Set ROC_ZIG_GLUE explicitly, or put ZigGlue.roc at vendor/glue/ZigGlue.roc" >&2
    exit 1
  fi

  CACHED="$CACHE_DIR/$COMMIT/ZigGlue.roc"
  if [ ! -f "$CACHED" ]; then
    mkdir -p "$(dirname "$CACHED")"
    URL="https://raw.githubusercontent.com/roc-lang/roc/${COMMIT}/src/glue/src/ZigGlue.roc"
    echo "fetch: $URL"
    if command -v curl >/dev/null 2>&1; then
      curl -fsSL "$URL" -o "$CACHED"
    elif command -v wget >/dev/null 2>&1; then
      wget -qO "$CACHED" "$URL"
    else
      echo "error: need curl or wget to fetch ZigGlue.roc" >&2
      exit 1
    fi
    # basic sanity: should look like a Roc glue script
    if ! grep -q 'make_glue\|roc_platform_abi' "$CACHED" 2>/dev/null; then
      echo "error: fetched file does not look like ZigGlue.roc (bad commit or 404 HTML?)" >&2
      rm -f "$CACHED"
      exit 1
    fi
  else
    echo "cache: $CACHED"
  fi
  ZIG_GLUE="$CACHED"
fi

if [ ! -f "$ZIG_GLUE" ]; then
  echo "error: ZigGlue.roc not found at $ZIG_GLUE" >&2
  exit 1
fi

echo "glue: $ZIG_GLUE → host/roc_platform_abi.zig"
roc glue "$ZIG_GLUE" host/ platform/main.roc
test -f host/roc_platform_abi.zig
echo "ok: host/roc_platform_abi.zig ($(wc -c < host/roc_platform_abi.zig) bytes)"
