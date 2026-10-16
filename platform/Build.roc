import Host

## Public build API. Pure graph construction + one effect to run it.
Build := [].{

    ## User-facing task (no id assigned yet).
    Cmd : {
        depends_on : List(Host.TaskId),
        program : Str,
        args : List(Str),
        description : Str,
        cwd : Str,
        env : List((Str, Str)),
        memory_budget : U64,
    }

    TaskId : Host.TaskId
    BuildGraph : Host.BuildGraph

    cmd :
        {
            program : Str,
            args : List(Str),
            description : Str,
            depends_on : List(Host.TaskId),
            cwd : Str,
            env : List((Str, Str)),
            memory_budget : U64,
        }
        -> Cmd
    cmd = |opts| {
        depends_on: opts.depends_on,
        program: opts.program,
        args: opts.args,
        description: opts.description,
        cwd: opts.cwd,
        env: opts.env,
        memory_budget: opts.memory_budget,
    }

    cmd_simple :
        {
            program : Str,
            args : List(Str),
            description : Str,
            depends_on : List(Host.TaskId),
            cwd : Str,
            env : List((Str, Str)),
        }
        -> Cmd
    cmd_simple = |opts| cmd({
        program: opts.program,
        args: opts.args,
        description: opts.description,
        depends_on: opts.depends_on,
        cwd: opts.cwd,
        env: opts.env,
        memory_budget: 0,
    })

    ## Turn a Cmd + index into a nominal Host.Task (annotation is required).
    to_host_task : Cmd, U64 -> Host.Task
    to_host_task = |c, idx| {
        id: idx,
        depends_on: c.depends_on,
        inputs: [],
        outputs: [],
        action: Cmd({ program: c.program, args: c.args }),
        description: c.description,
        cwd: c.cwd,
        env: c.env,
        memory_budget: c.memory_budget,
    }

    graph : List(Cmd) -> Host.BuildGraph
    graph = |cmds| {
        tasks = List.map_with_index(cmds, |c, idx| to_host_task(c, idx))

        # Same shape as original graph — annotation on graph forces Host.BuildGraph
        { tasks: tasks }
    }

    run! : Host.BuildGraph => Try({}, [BuildFailed(Str)])
    run! = |g| Host.run_graph!(g)
}
