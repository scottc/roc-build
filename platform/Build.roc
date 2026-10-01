import Host

## Public build API. Pure graph construction + one effect to run it.
Build := [].{
    graph : List(Host.Task) -> Host.BuildGraph
    graph = |tasks| {
        tasks: tasks,
    }

    ## Build a command task. Pass [] / "" for unused optional-ish fields.
    cmd :
        {
            id : Host.TaskId,
            depends_on : List(Host.TaskId),
            inputs : List(Str),
            outputs : List(Str),
            program : Str,
            args : List(Str),
            description : Str,
            cwd : Str,
            env : List((Str, Str)),
        }
        -> Host.Task
    cmd = |opts| {
        id: opts.id,
        depends_on: opts.depends_on,
        inputs: opts.inputs,
        outputs: opts.outputs,
        action: Cmd({ program: opts.program, args: opts.args }),
        description: opts.description,
        cwd: opts.cwd,
        env: opts.env,
    }

    run! : Host.BuildGraph => Try({}, [BuildFailed(Str)])
    run! = |g| Host.run_graph!(g)
}
