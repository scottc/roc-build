#
# A backup build recipe
# just incase we're having "chicken & egg" build problems.
# Publish: gen glue → build host → bundle platform
#

./gen_glue.sh

cp -a vendor/targets/x64musl/. platform/targets/x64musl/

zig build-lib \
host/host.zig \
-fPIC \
-OReleaseSafe \
-target x86_64-linux-musl \
-lc \
-femit-bin=platform/targets/x64musl/libhost.a

roc bundle \
platform/main.roc \
platform/Build.roc \
platform/Host.roc \
platform/Log.roc \
platform/targets/x64musl/crt1.o \
platform/targets/x64musl/libc.a \
platform/targets/x64musl/libcompiler_rt.a \
"platform/targets/x64musl/libzigc.a \
platform/targets/x64musl/libhost.a
