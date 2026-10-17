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
    Log.info!("CI:")
    Log.info!("gen glue -> static test host -> static test platform")

    # some reason, ci fails without targets-out dir?
    mkdir_targets_out = BuildCmd.new({
        program: "mkdir",
        args: ["-p", "platform/targets-out/x64musl/"],
        description: "Ensure 'platform/targets-out/x64musl/' dir."
    })
    .with_memory(Mem.gb(1))

    gen_glue = BuildCmd.new({
        program: "sh",
        args: ["-c", "scripts/gen_glue.sh"],
        description: "Generate host/roc_platform_abi.zig",
    })
    .with_memory(Mem.gb(1))

    # cp = BuildCmd.new({
    #     program: "cp",
    #     args: ["-a", "vendor/targets/x64musl/.", "platform/targets/x64musl/"],
    #     description: "Install platform dependencies",
    # })
    # .with_memory(Mem.mb(256))

    zig_test = BuildCmd.new({
            program: "zig",
            args: ["test", "host/host.zig"],
            description: "Build Zig Host",
        })
        .depends_on([gen_glue])
        .with_memory(Mem.gb(1))

    roc_test_platform = BuildCmd.new({
            program: "roc",
            args: ["test", "platform/main.roc"],
            description: "Build Roc Host",
        })
        .depends_on([mkdir_targets_out]) # gen_glue
        .with_memory(Mem.gb(1))

    roc_test_self = BuildCmd.new({
            program: "roc",
            args: ["test", "scripts/ci.roc"],
            description: "Build Roc Host",
        })
        .depends_on([]) # gen_glue
        .with_memory(Mem.gb(1))

    roc_test_publish = BuildCmd.new({
            program: "roc",
            args: ["test", "scripts/publish.roc"],
            description: "Build Roc Host",
        })
        .depends_on([]) # gen_glue
        .with_memory(Mem.gb(1))

    graph = Build.graph_with(
        [
            mkdir_targets_out,
            gen_glue,
            zig_test,
            roc_test_platform,
            roc_test_self,
            roc_test_publish
        ],
        {
            max_memory: Mem.gb(6), #TODO: Match GHA
            max_parallel: 8, #TODO: Match GHA
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
