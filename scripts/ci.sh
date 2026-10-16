#
# A backup build recipe
# just incase we're having "chicken & egg" build problems.
# CI: gen glue → static test host → static test platform
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
