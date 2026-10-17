#!/usr/bin/env sh

# TODO: we cannot build self-hosted
# because we need the zig binaries to exist before we can run
# chicken & egg bootstrapping problem
# We could use a previously built zig binaries,
# OR! we can compile the current version with zig...
# AND THEN... we can continue.

# Bootstrap CI — do not self-host via roc-build (chicken & egg).
set -eu

ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

log() { printf '[ci] %s\n' "$*"; }

log "generate glue"
sh scripts/gen_glue.sh

log "zig test host"
zig test host/host.zig

log "roc test platform"
roc test platform/main.roc



# mkdir -p platform/targets-out/x64musl/

#sh -c scripts/gen_glue.sh

# cp -a vendor/targets/x64musl/. platform/targets-out/x64musl/

#zig test host/host.zig

# Do we want zig build and roc check?

# zig build-lib host/host.zig \
# -femit-bin=platform/targets-out/x64musl/libhost.a \
# -fPIC \
# -OReleaseSafe \
# -target x86_64-linux-musl \
# -lc


# roc test scripts/ci.roc
#
# roc test scripts/publish.roc
