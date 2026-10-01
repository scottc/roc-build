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
