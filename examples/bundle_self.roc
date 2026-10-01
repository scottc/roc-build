app [main!] {
	pf: platform "https://github.com/scottc/roc-build/releases/download/0.0.1-pre-alpha-test1/8jZuyEFpCc7ep6yu2iXBT4cAYoxZdjTk5kxShUCMXqgx.tar.zst",
	roc: "nightly-2026-09-27-a3ce7f1",
}

import pf.Build
import pf.Log

main! : List(Str) => Try({}, [Exit(I32)])
main! = |_args| {
	Log.info!("Build host, build & bundle platform.")

	# pwd_id = 0
	# pwd = Build.cmd({
	# 	id: pwd_id,
	# 	depends_on: [],
	# 	inputs: [],
	# 	outputs: [],
	# 	program: "pwd",
	# 	args: [],
	# 	description: "Print working directory",
	# 	cwd: "",
	# 	env: [],
	# })

	cp_id = 1
	cp = Build.cmd({
		id: cp_id,
		depends_on: [
		    # pwd_id
		],
		inputs: [
      #       "vendor/targets/x64musl/crt1.o",
      #       "vendor/targets/x64musl/libc.a",
      #       "vendor/targets/x64musl/libcompiler_rt.a",
		    # "vendor/targets/x64musl/libzigc.a",
		],
		outputs: [
		    # "platform/targets/x64musl/crt1.o",
      #       "platform/targets/x64musl/libc.a",
      #       "platform/targets/x64musl/libcompiler_rt.a",
      #       "platform/targets/x64musl/libzigc.a",
		],
		program: "cp",
		args: ["-a", "vendor/targets/x64musl/.", "platform/targets/x64musl/"],
		description: "Install platform dependencies",
		cwd: "",
		env: [],
	})

	zig_build_lib_id = 2
	zig_build_lib = Build.cmd({
		id: zig_build_lib_id,
		depends_on: [],
		inputs: [
    		# "host/host.zig",
    		# "host/roc_platform_abi.zig"
		],
		outputs: [
		    # "platform/targets/x64musl/libhost.a"
		],
		program: "zig",
		args: [
		    "build-lib",
			"-fPIC",
			"-OReleaseSafe",
			"-target", "x86_64-linux-musl",
			"-lc",
			"host/host.zig",
			"-femit-bin=platform/targets/x64musl/libhost.a"
		],
		description: "Build Zig Host",
		cwd: "",
		env: [],
	})

	# roc bundle platform/main.roc platform/targets/x64musl/*
	roc_bundle_id = 3
	roc_bundle = Build.cmd({
		id: roc_bundle_id,
		depends_on: [cp_id, zig_build_lib_id],
		inputs: [
      #       "platform/main.roc",
      #       "platform/Build.roc",
      #       "platform/Host.roc",
		    # "platform/Log.roc",
		    # "platform/targets/x64musl/crt1.o",
      #       "platform/targets/x64musl/libc.a",
      #       "platform/targets/x64musl/libcompiler_rt.a",
      #       "platform/targets/x64musl/libzigc.a",
      #       "platform/targets/x64musl/libhost.a",
		],
		outputs: [
		    # "CXzHUmjdummJLMyox6aVnjE5xEL3cC1BKm7nijtgaCVY.tar.zst"
		],
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
		cwd: "",
		env: [],
	})

	graph = Build.graph([
	    # pwd,
		cp,
		zig_build_lib,
		roc_bundle,
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
