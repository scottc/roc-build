# Roc-Build

A general purpose reproduceable parallel task runner, that is 100% fully user configured in roc-lang.

That was originally designed as a concurrent build system for roc, to build non-trivial roc platforms & apps, as a replacement for `build.zig` & `flake.nix`.

## About

Build roc lets you build your app and/or platform concurrently with a declarative dependency graph, in a reproduceable declarative environment.

I built this to service the real-world use case are the `scottc/godot-roc` & `scottc/survivepg` projects.

## Example

```roc
app [main!] {
    pf: platform "../platform/main.roc",
}

import pf.Mem
import pf.Build
import pf.BuildCmd
import pf.Log

main! : List(Str) => Try({}, [Exit(I32)])
main! = |_args| {
    #limits = parse_limits(args) # { max_memory, max_parallel }
    Log.info!("CI: gen glue → static test host → static test platform")

    gen_glue = BuildCmd.new({
        program: "sh",
        args: ["-c", "scripts/gen_glue.sh"],
        description: "Generate host/roc_platform_abi.zig",
    })
    .with_memory(Mem.gb(1))

    cp = BuildCmd.new({
        program: "cp",
        args: ["-a", "vendor/targets/x64musl/.", "platform/targets/x64musl/"],
        description: "Install platform dependencies",
    })
    .with_memory(Mem.mb(256))

    zig_build_lib =
        BuildCmd.new({
            program: "zig",
            args: [
                "build-lib",
                "-fPIC",
                "-OReleaseSafe",
                "-target", "x86_64-linux-musl",
                "-lc",
                "host/host.zig",
                "-femit-bin=platform/targets/x64musl/libhost.a",
            ],
            description: "Build Zig Host",
        })
        .depends_on([gen_glue])
        .with_memory(Mem.gb(1))

    graph = Build.graph_with(
        [gen_glue, cp, zig_build_lib],
        {
            max_memory: Mem.gb(2),
            max_parallel: 4,
        },
    )

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

- `zig` (if building this build platform from source)
- `libc` runtime dependency (app development)
- `roc` (app development)

## Build this platform, with this platform!

Note: nix & blueprint, is optional... and will be replaced with self-hosted implementations.

```sh
# roc run ./scripts/publish.roc
nix run github:lukewilliamboswell/roc-blueprint/0.5.0 -- run publish
```

## Bootstrap from scratch.

```sh
# compile self from scratch
./scripts/ci.sh

# self-hosted compile self
roc run scripts/ci.roc
```

## Features / Roadmap

- [x] It accepts cli args, stdin/stdout & follows cli conventions to be used in a wider pipeline & toolchain.
- [x] It runs a task graph
- [ ] Tasks have dependencies (without passing around ids; aka a nice user interface experience.)
- [x] It schedules concurrently (wave based)
- [ ] It schedules concurrently (eager based)
- [x] It has memory limits via cli flag `--max-memory=16gb`
- [x] It has memory budgets per task (so they can be scheduled or cancelled appropriately).
- [x] It schedules with parallel task limits `--max-parallel=4`
- [ ] It has a lock file
- [ ] It has declarative reproduceable environments
- [ ] It has sandboxing to avoid being influced by unwanted side-effects
- [ ] It has shells you can enter
- [ ] It hashes automatically (no need to specify exact files, for a nice user experience)
- [ ] It has build commands with optional fields... only specify what you need, for a nice user experience.
- [ ] It caches
- [ ] It's composable, and can download hashed dependencies into a cache.
- [ ] It works across many platforms..
- [ ] It can take nix flakes as inputs.
- [ ] It has a github actions CI intergration template & guide.

## Supported Targets

- [x] x64musl
- [ ] ...
- [ ] ...
- [ ] ...
