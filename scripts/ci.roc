app [main!] {
    pf: platform "../platform/main.roc",
}

import pf.Build
import pf.Log

main! : List(Str) => Try({}, [Exit(I32)])
main! = |_args| {
    Log.info!("CI: glue → host → bundle")

    # 0) Generate ABI from current platform/Host types
    gen_glue = Build.cmd_simple({
        program: "roc",
        args: [
            "glue",
            # Resolve ZigGlue via env in a small wrapper, or pass absolute path.
            # Simplest honest option: require ROC_ZIG_GLUE in the environment.
            "${/* see note below */}",
        ],
        description: "Generate host/roc_platform_abi.zig",
        depends_on: [],
        cwd: "",
        env: [],
    })

    # Prefer a shell one-liner so path resolution stays in one place:
    gen_glue = Build.cmd_simple({
        program: "sh",
        args: ["-c", "scripts/gen_glue.sh"],
        description: "Generate host/roc_platform_abi.zig",
        depends_on: [],
        cwd: "",
        env: [],
    })

    cp = Build.cmd_simple({
        program: "cp",
        args: ["-a", "vendor/targets/x64musl/.", "platform/targets/x64musl/"],
        description: "Install platform dependencies",
        depends_on: [],
        cwd: "",
        env: [],
    })

    zig_build_lib = Build.cmd_simple({
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
        depends_on: [0],   # after glue
        cwd: "",
        env: [],
    })

    roc_bundle = Build.cmd_simple({
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
        depends_on: [1, 2],  # cp + zig (indices after you order the list)
        cwd: "",
        env: [],
    })

    graph = Build.graph([
        gen_glue,       # 0
        cp,             # 1
        zig_build_lib,  # 2
        roc_bundle,     # 3
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
