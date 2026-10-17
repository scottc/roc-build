#
# A backup build recipe
# just incase we're having "chicken & egg" build problems.
# Publish: gen glue → build host → bundle platform
#

mkdir -p platform/targets-out/x64musl/
mkdir -p bundle-out/
sh -c scripts/gen_glue.sh
cp -a vendor/targets/x64musl/. platform/targets-out/x64musl/

zig build-lib host/host.zig \
-femit-bin=platform/targets-out/x64musl/libhost.a \
-fPIC \
-OReleaseSafe \
-target x86_64-linux-musl \
-lc

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

cd ../

mv platform/*.tar.zst bundle-out/
