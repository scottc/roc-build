import Host
import BuildCmd

## Graph construction + run.
Build := [].{

    #Cmd : BuildCmd

    find_index_by_key : List(BuildCmd), Str -> Host.TaskId
    find_index_by_key = |cmds, k|
        match List.find_first_index(cmds, |c| BuildCmd.key(c) == k) {
            Ok(i) => i
            Err(NotFound) => 0
        }

    to_host_task : BuildCmd, List(BuildCmd), U64 -> Host.Task
    to_host_task = |cmd, all, idx| {
        dep_ids = List.map(cmd.depends_on_keys, |k| find_index_by_key(all, k))

        {
            id: idx,
            depends_on: dep_ids,
            inputs: [],
            outputs: [],
            action: Cmd({ program: cmd.program, args: cmd.args }),
            description: cmd.description,
            cwd: cmd.cwd,
            env: cmd.env,
            memory_budget: cmd.memory_budget,
        }
    }

    graph : List(BuildCmd) -> Host.BuildGraph
    graph = |cmds| graph_with(cmds, { max_memory: 0, max_parallel: 0 })

    graph_with :
        List(BuildCmd),
        { max_memory : U64, max_parallel : U64 }
        -> Host.BuildGraph
    graph_with = |cmds, limits| {
        tasks = List.map_with_index(cmds, |cmd, idx| to_host_task(cmd, cmds, idx))
        {
            tasks: tasks,
            max_memory: limits.max_memory,
            max_parallel: limits.max_parallel,
        }
    }

    run! : Host.BuildGraph => Try({}, [BuildFailed(Str)])
    run! = |g| Host.run_graph!(g)
}
