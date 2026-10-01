app [main!] {
    pf: platform "../platform/main.roc",
    roc: "nightly-2026-09-27-a3ce7f1",
}

import pf.Build
import pf.Log

# Graph (time ≈ sleep seconds):
#
#   sleepA(2)  sleepB(2)  sleepC(2)   lint(1)   assets(1)
#       \         |        /              \       /
#        \        |       /                \     /
#              link(1)                   package waits on link+assets
#                  \                      /
#                   \                    /
#                      package(1)
#                         |
#                      test(1)
#
# Critical path ≈ 2+1+1+1 = 5s sequential for the main chain,
# but A/B/C + lint + assets overlap → wall clock should be ~5s, not ~11s.

main! : List(Str) => Try({}, [Exit(I32)])
main! = |_args| {
    Log.info!("parallel build demo")

    # --- independent compile units (should run concurrently) ---
    compile_a = Build.cmd({
        id: 1,
        depends_on: [],
        inputs: ["src/a.roc"],
        outputs: ["out/a.o"],
        program: "sleep",
        args: ["2"],
        description: "Compile A (2s)",
        cwd: "",
        env: [],
    })
    compile_b = Build.cmd({
        id: 2,
        depends_on: [],
        inputs: ["src/b.roc"],
        outputs: ["out/b.o"],
        program: "sleep",
        args: ["2"],
        description: "Compile B (2s)",
        cwd: "",
        env: [],
    })
    compile_c = Build.cmd({
        id: 3,
        depends_on: [],
        inputs: ["src/c.roc"],
        outputs: ["out/c.o"],
        program: "sleep",
        args: ["2"],
        description: "Compile C (2s)",
        cwd: "",
        env: [],
    })

    # independent side work
    lint = Build.cmd({
        id: 4,
        depends_on: [],
        inputs: ["src"],
        outputs: [],
        program: "sleep",
        args: ["1"],
        description: "Lint (1s)",
        cwd: "",
        env: [],
    })
    assets = Build.cmd({
        id: 5,
        depends_on: [],
        inputs: ["assets"],
        outputs: ["out/assets.pack"],
        program: "sleep",
        args: ["1"],
        description: "Pack assets (1s)",
        cwd: "",
        env: [],
    })

    # join compiles
    link = Build.cmd({
        id: 10,
        depends_on: [1, 2, 3],
        inputs: ["out/a.o", "out/b.o", "out/c.o"],
        outputs: ["out/app"],
        program: "sleep",
        args: ["1"],
        description: "Link app (1s)",
        cwd: "",
        env: [],
    })

    # package needs link + assets
    package1 = Build.cmd({
        id: 20,
        depends_on: [10, 5],
        inputs: ["out/app", "out/assets.pack"],
        outputs: ["out/app.tar"],
        program: "sleep",
        args: ["1"],
        description: "Package (1s)",
        cwd: "",
        env: [],
    })

    # tests after package
    test = Build.cmd({
        id: 30,
        depends_on: [20],
        inputs: ["out/app.tar"],
        outputs: [],
        program: "sleep",
        args: ["1"],
        description: "Test (1s)",
        cwd: "",
        env: [],
    })

    # final report after test + lint
    report = Build.cmd({
        id: 40,
        depends_on: [30, 4],
        inputs: [],
        outputs: [],
        program: "echo",
        args: ["BUILD OK"],
        description: "Report",
        cwd: "",
        env: [],
    })

    graph = Build.graph([
        compile_a,
        compile_b,
        compile_c,
        lint,
        assets,
        link,
        package1,
        test,
        report,
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
