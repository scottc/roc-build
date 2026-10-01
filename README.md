# Roc-Build

A concurrent build system for roc, to build non-trivial roc platforms & apps, a replacement for build.zig.

## About

Build roc lets you build your app and/or platform concurrently with declarative dependency graph.

I built this to service the real-world use case that is the `scottc/godot-roc` project.

## Bootstrap, Build & Run

```sh
# Install zig 0.16.0 & roc nightly-2026-09-27-a3ce7f1
# ...

# for x64musl fetch; crt1.o,libc.a,libcompiler_rt.a,libzigc.a
# (these are in the vendor folder)
# then... place them here... platform/targets/x64musl/
cp vendor/targets/x64musl/* platform/targets/x64musl/

# build the platform
zig build-lib -fPIC -OReleaseSafe -target x86_64-linux-musl \
  -lc \
  host/host.zig -femit-bin=platform/targets/x64musl/libhost.a

# build & run the demo build app...
roc run examples/hello_build.roc
#info: parallel build demo
#info: wave: 5 tasks in parallel
#info: start Compile A (2s) (id=1)
#info: start Compile B (2s) (id=2)
#info: start Compile C (2s) (id=3)
#info: start Lint (1s) (id=4)
#info:   $ /nix/store/xjl7p8dvyk2j53kqf7f43kdj4ypbxz7g-coreutils-9.11/bin/sleep
#info:       2
#info: start Pack assets (1s) (id=5)
#info:   $ /nix/store/xjl7p8dvyk2j53kqf7f43kdj4ypbxz7g-coreutils-9.11/bin/sleep
#info:       2
#info:   $ /nix/store/xjl7p8dvyk2j53kqf7f43kdj4ypbxz7g-coreutils-9.11/bin/sleep
#info:       2
#info:   $ /nix/store/xjl7p8dvyk2j53kqf7f43kdj4ypbxz7g-coreutils-9.11/bin/sleep
#info:       1
#info:   $ /nix/store/xjl7p8dvyk2j53kqf7f43kdj4ypbxz7g-coreutils-9.11/bin/sleep
#info:       1
#info: done  Compile A (2s)
#info: done  Compile B (2s)
#info: done  Compile C (2s)
#info: done  Lint (1s)
#info: done  Pack assets (1s)
#info: wave: 1 tasks in parallel
#info: start Link app (1s) (id=10)
#info:   $ /nix/store/xjl7p8dvyk2j53kqf7f43kdj4ypbxz7g-coreutils-9.11/bin/sleep
#info:       1
#info: done  Link app (1s)
#info: wave: 1 tasks in parallel
#info: start Package (1s) (id=20)
#info:   $ /nix/store/xjl7p8dvyk2j53kqf7f43kdj4ypbxz7g-coreutils-9.11/bin/sleep
#info:       1
#info: done  Package (1s)
#info: wave: 1 tasks in parallel
#info: start Test (1s) (id=30)
#info:   $ /nix/store/xjl7p8dvyk2j53kqf7f43kdj4ypbxz7g-coreutils-9.11/bin/sleep
#info:       1
#info: done  Test (1s)
#info: wave: 1 tasks in parallel
#info: start Report (id=40)
#info:   $ /nix/store/xjl7p8dvyk2j53kqf7f43kdj4ypbxz7g-coreutils-9.11/bin/echo
#info:       BUILD OK
#BUILD OK
#info: done  Report
#info: all tasks finished
```

## Build & Run self.

```sh
# TODO: package & release.
# Then we can dog-food ARBS, to build ARBS itself.
```

## Features / Roadmap

- [x] It runs the graph
- [x] It runs concurrently
- [ ] It hashes
- [ ] It caches
- [ ] It has a github actions CI intergration template & guide.

## Supported Targets

- [x] x86_64-linux-musl
- [ ] ...
- [ ] ...
- [ ] ...

