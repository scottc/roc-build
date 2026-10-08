app [main!] {
	pf: platform "../platform/main.roc",
	roc: "nightly-2026-10-06-c34079d",
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
