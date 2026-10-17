app [main!] {
    pf: platform "../platform/main.roc",
}

import pf.Build
import pf.BuildCmd
import pf.Log

main! : List(Str) => Try({}, [Exit(I32)])
main! = |_args| {
    Log.info!("Publish: gen glue → build host → bundle platform")

    gen_glue = BuildCmd.new({
        program: "sh",
        args: ["-c", "scripts/gen_glue.sh"],
        description: "Generate host/roc_platform_abi.zig",
    })

    cp = BuildCmd.new({
        program: "cp",
        args: ["-a", "vendor/targets/x64musl/.", "platform/targets/x64musl/"],
        description: "Install platform dependencies",
    })

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

    roc_bundle =
        BuildCmd.new({
            program: "roc",
            args: [
                "bundle",
                "platform/main.roc",
                "platform/Build.roc",
                "platform/Host.roc",
                "platform/Log.roc",
                "platform/targets/x64musl/crt1.o",
                "platform/targets/x64musl/libc.a",
                "platform/targets/x64musl/libcompiler_rt.a",
                "platform/targets/x64musl/libzigc.a",
                "platform/targets/x64musl/libhost.a",
            ],
            description: "Roc Bundle",
        })
        .depends_on([cp, zig_build_lib])

    # TODO: write into bundle-out/
    # TODO: GHA to publish a release.

    graph = Build.graph([gen_glue, cp, zig_build_lib, roc_bundle])

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
