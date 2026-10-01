# Roc-Build

A concurrent build system for roc, to build non-trivial roc platforms & apps, a replacement for build.zig.

## About

Build roc lets you build your app and/or platform concurrently with declarative dependency graph.

I built this to service the real-world use case that is the `scottc/godot-roc` project.

## Example
```roc
app [main!] {
	pf: platform "https://github.com/scottc/roc-build/releases/download/0.0.1-pre-alpha-test1/8jZuyEFpCc7ep6yu2iXBT4cAYoxZdjTk5kxShUCMXqgx.tar.zst",
	roc: "nightly-2026-09-27-a3ce7f1",
}

import pf.Build
import pf.Log

main! : List(Str) => Try({}, [Exit(I32)])
main! = |_args| {
	Log.info!("Hello World.")

  pwd_id = 0
	pwd = Build.cmd({
		id: pwd_id,
		depends_on: [],
	 	inputs: [],
		outputs: [],
		program: "pwd",
	 	args: [],
	 	description: "Print working directory",
	 	cwd: "",
	 	env: [],
	})

	graph = Build.graph([
		pwd,
	])

	match Build.run!(graph) {
		Ok({}) => {
			Log.info!("all tasks finished")
			Ok({})
		}
		Err(BuildFailed(msg)) => {
			Log.error!(msg)
			Err(Exit(1))
		}
	}
}
```

## Requirements
- `zig 0.16.0` (if building this build platform from source)
- `libc` runtime dependency (app development)
- `roc` `nightly-2026-09-27-a3ce7f1` (app development)

## Build & Run this platform, with this platform!

```sh
roc run examples/bundle_self.roc
```

## Bootstrap from scratch, Build & Run.

```sh
# Install zig 0.16.0 & roc nightly-2026-09-27-a3ce7f1
# Note: we also depend on libc.
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

## Features / Roadmap

- [x] It runs the graph
- [x] It runs concurrently (wave based)
- [ ] It runs concurrently (eager based)
- [ ] It hashes
- [ ] It caches
- [ ] It has a github actions CI intergration template & guide.

## Supported Targets

- [x] x86_64-linux-musl
- [ ] ...
- [ ] ...
- [ ] ...
