platform "build"
    requires {} { main! : List(Str) => Try({}, [Exit(I32), ..]) }
    exposes [Build, Log]
    packages {
        roc: "nightly-2026-09-27-a3ce7f1",
    }
    provides { "roc_main": main_for_host! }
    hosted {
        "roc_build_run_graph": Host.run_graph!,
        "roc_log_info": Host.log_info!,
        "roc_log_warn": Host.log_warn!,
        "roc_log_error": Host.log_error!,
        "roc_cmd_exec": Host.cmd_exec!,
        "roc_file_read_bytes": Host.file_read_bytes!,
        "roc_file_write_bytes": Host.file_write_bytes!,
        "roc_path_exists": Host.path_exists!,
    }
    targets: {
        inputs_dir: "targets/",

        x64musl: { inputs: ["crt1.o", "libhost.a", app, "libc.a", "libzigc.a", "libcompiler_rt.a"] },
        #x64musl: { inputs: ["libhost.a", app] },

        # x64mac: { inputs: ["libhost.a", app] },
        # arm64mac: { inputs: ["libhost.a", app] },
        # x64musl: { inputs: ["crt1.o", "libhost.a", app, "libc.a", "libzigc.a", "libcompiler_rt.a"] },
        # x64v1musl: { inputs: ["crt1.o", "libhost.a", app, "libc.a", "libzigc.a", "libcompiler_rt.a"] },
        # arm64musl: { inputs: ["crt1.o", "libhost.a", app, "libc.a", "libzigc.a", "libcompiler_rt.a"] },
        # arm64v1musl: { inputs: ["crt1.o", "libhost.a", app, "libc.a", "libzigc.a", "libcompiler_rt.a"] },
        # x64win: { inputs: ["host.lib", app] },
        # arm64win: { inputs: ["host.lib", app] },
    }

import Host
import Build
import Log

main_for_host! : List(Str) => I32
main_for_host! = |args| {
    result = main!(args)
    match result {
        Ok({}) => 0
        Err(Exit(code)) => code
        Err(other) => {
            Host.log_error!("ERROR: ${Str.inspect(other)}")
            -1
        }
    }
}
