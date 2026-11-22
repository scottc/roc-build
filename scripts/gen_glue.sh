#!/usr/bin/env sh
set -eu

#
# 1) Resolve ZigGlue.roc:
#    - ROC_ZIG_GLUE env, or
#    - vendor/glue/ZigGlue.roc, or
#    - fetch from roc-lang/roc at the commit matching `roc version`
# 2) Run: roc glue <ZigGlue.roc> host/ platform/main.roc
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
  VERSION_LINE="$(roc version 2>/dev/null || roc --version 2>/dev/null || true)"
  COMMIT=""

  # nightly-YYYY-MM-DD-<hash>
  COMMIT="$(printf '%s\n' "$VERSION_LINE" | sed -n 's/.*nightly-[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}-\([0-9a-f]\{7,40\}\).*/\1/p')"

  # 0.1.0_RC1 (and future RCs) — hard-map known tags → full commit
  if [ -z "$COMMIT" ]; then
    case "$VERSION_LINE" in
      *"0.1.0_RC1"*)
        # https://github.com/roc-lang/roc/releases/tag/0.1.0_RC1
        COMMIT="15177e91f62cafddf5336c455e00e9f05427ac16"
        ;;
      # add more RC tags here as they appear
    esac
  fi

  # bare "version X.Y.Z" with no tag info — leave COMMIT empty (error below)

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
