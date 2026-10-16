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

    # TODO: zig test
    # TODO: roc test
    # TODO: roc check
    # TODO: roc build an example...

    graph = Build.graph_with(
        [gen_glue, cp, zig_build_lib],
        {
            max_memory: Mem.gb(2), # limits.max_memory,   # e.g. Mem.gb(2) from --memory=2gb
            max_parallel: 4, # limits.max_parallel,
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

# parse_size : Str -> Try(U64, [BadSize(Str)])
# parse_size = |_s| {
#     #lower = Str.to_lower(s)
#     # accept 2gb, 2GiB, 512mb, 1024kb, raw bytes
#     #...
#     Ok(2 * 1024 * 1024 * 1024)
# }
#
# parse_args : List(Str) -> { max_memory : U64, max_parallel : U64, rest : List(Str) }
# parse_args = |_args| {
#     # walk flags:
#     #   --memory=2gb | --memory 2gb
#     #   --parallel=4 | --parallel 4
#     # defaults: memory = 0 (unlimited) or a safe default; parallel = 0 (unlimited)
#     #...
#     {
#         max_memory : 2 * 1024 * 1024 * 1024,
#         max_parallel : 2 * 1024 * 1024 * 1024,
#         rest : ["", ""],
#     }
# }
