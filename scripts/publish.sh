#!/usr/bin/env sh
# scripts/publish.sh — bootstrap publish (no self-hosted roc-build)
#
# Chicken & egg: we cannot use roc-build to build roc-build until a host
# binary exists. This script uses zig + roc on PATH directly. And
# working around this fact, creates a permenent "feature lag" footgun.
#
# It's better to just use an alternative build system, like this sh script.
#
# Requires: roc, zig, git, curl|wget (for glue fetch), gh (for release)
# Env:      GITHUB_TOKEN (required for release)
#           GITHUB_REPOSITORY optional (owner/name); falls back to gh repo view
#           PUBLISH_TAG optional explicit tag; default nightly-YYYY-MM-DD-<sha7>
#           SKIP_RELEASE=1 to only build/bundle (no gh release)
# Useage:
# chmod +x scripts/publish.sh
#
# # build + release
# GITHUB_TOKEN=… ./scripts/publish.sh
#
# # build only (no gh)
# SKIP_RELEASE=1 ./scripts/publish.sh
#
# # fixed tag
# PUBLISH_TAG=v0.1.0 GITHUB_TOKEN=… ./scripts/publish.sh
#

set -eu

ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

log() { printf '[publish] %s\n' "$*"; }
die() { printf '[publish] error: %s\n' "$*" >&2; exit 1; }

command -v roc >/dev/null 2>&1 || die "roc not on PATH"
command -v zig >/dev/null 2>&1 || die "zig not on PATH"

# ---------------------------------------------------------------------------
# 1. glue → host → bundle
# ---------------------------------------------------------------------------

log "mkdir targets-out + bundle-out"
mkdir -p platform/targets-out/x64musl
mkdir -p bundle-out

log "generate host/roc_platform_abi.zig"
sh scripts/gen_glue.sh

log "install static deps (crt, libc, …)"
cp -a vendor/targets/x64musl/. platform/targets-out/x64musl/

log "build zig host → platform/targets-out/x64musl/libhost.a"
zig build-lib \
  host/host.zig \
  -femit-bin=platform/targets-out/x64musl/libhost.a \
  -fPIC \
  -OReleaseSafe \
  -target x86_64-linux-musl \
  -lc

log "roc bundle (cwd=platform/)"
(
  cd platform
  roc bundle \
    main.roc \
    Build.roc \
    Host.roc \
    Log.roc \
    targets-out/x64musl/crt1.o \
    targets-out/x64musl/libc.a \
    targets-out/x64musl/libcompiler_rt.a \
    targets-out/x64musl/libzigc.a \
    targets-out/x64musl/libhost.a
)

log "move bundle → bundle-out/"
# shellcheck disable=SC2086
mv -f platform/*.tar.zst bundle-out/

BUNDLE="$(ls -1 bundle-out/*.tar.zst 2>/dev/null | head -n1 || true)"
[ -n "$BUNDLE" ] && [ -f "$BUNDLE" ] || die "no .tar.zst in bundle-out/"
HASH="$(basename "$BUNDLE" .tar.zst)"
log "bundle ready: $BUNDLE (hash=$HASH)"

if [ "${SKIP_RELEASE:-}" = "1" ]; then
  log "SKIP_RELEASE=1 — done (no gh release)"
  exit 0
fi

# ---------------------------------------------------------------------------
# 2. GitHub release + single copy-paste app header
# ---------------------------------------------------------------------------

command -v gh >/dev/null 2>&1 || die "gh CLI not found"
[ -n "${GITHUB_TOKEN:-}" ] || die "GITHUB_TOKEN required"

REPO="${GITHUB_REPOSITORY:-}"
if [ -z "$REPO" ]; then
  REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)"
fi
[ -n "$REPO" ] || die "GITHUB_REPOSITORY unset and gh repo view failed"

SHA="$(git rev-parse --short=7 HEAD 2>/dev/null || echo nogit)"
if [ -n "${PUBLISH_TAG:-}" ]; then
  TAG="$PUBLISH_TAG"
else
  TAG="nightly-$(date -u +%Y-%m-%d)-$SHA"
fi

STAGING=release-assets
rm -rf "$STAGING"
mkdir -p "$STAGING"

ASSET="$STAGING/${HASH}.tar.zst"
cp -f "$BUNDLE" "$ASSET"
URL="https://github.com/${REPO}/releases/download/${TAG}/$(basename "$ASSET")"

NOTES="$STAGING/NOTES.md"
{
  echo "## roc-build ${TAG}"
  echo
  echo "Commit: \`${SHA}\`"
  echo
  echo "### Asset"
  echo
  echo "- file: \`$(basename "$ASSET")\`"
  echo "- url: \`${URL}\`"
  echo
  echo "### App header (copy & paste)"
  echo
  echo '```roc'
  echo 'app [main!] {'
  echo "    pf: platform \"${URL}\","
  echo '}'
  echo '```'
  echo
  echo "Target: **x86_64-linux-musl**"
  echo
  echo "Built with bootstrap \`scripts/publish.sh\` (zig + roc on PATH), not self-hosted roc-build."
} >"$NOTES"

log "creating release ${TAG}"
gh release create "$TAG" "$ASSET" \
  --title "roc-build ${TAG}" \
  --notes-file "$NOTES"

log "published ${TAG}"
log "app header:"
log "  pf: platform \"${URL}\","
