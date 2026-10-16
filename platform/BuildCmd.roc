## One build command (nominal record + methods).
BuildCmd := {
    depends_on_keys : List(Str),
    program : Str,
    args : List(Str),
    description : Str,
    cwd : Str,
    env : List((Str, Str)),
    memory_budget : U64,
}.{

    ## Only required fields; everything else defaults.
    new : { program : Str, args : List(Str), description : Str } -> BuildCmd
    new = |opts| {
        depends_on_keys: [],
        program: opts.program,
        args: opts.args,
        description: opts.description,
        cwd: "",
        env: [],
        memory_budget: 0,
    }

    ## Stable key for matching this cmd inside a graph list.
    key : BuildCmd -> Str
    key = |cmd|
        "${cmd.description}\u(1f)${cmd.program}\u(1f)${Str.join_with(cmd.args, "\u(1f)")}"

    depends_on : BuildCmd, List(BuildCmd) -> BuildCmd
    depends_on = |cmd, deps| {
        depends_on_keys: List.map(deps, key),
        program: cmd.program,
        args: cmd.args,
        description: cmd.description,
        cwd: cmd.cwd,
        env: cmd.env,
        memory_budget: cmd.memory_budget,
    }

    with_cwd : BuildCmd, Str -> BuildCmd
    with_cwd = |cmd, cwd| {
        depends_on_keys: cmd.depends_on_keys,
        program: cmd.program,
        args: cmd.args,
        description: cmd.description,
        cwd: cwd,
        env: cmd.env,
        memory_budget: cmd.memory_budget,
    }

    with_env : BuildCmd, List((Str, Str)) -> BuildCmd
    with_env = |cmd, env| {
        depends_on_keys: cmd.depends_on_keys,
        program: cmd.program,
        args: cmd.args,
        description: cmd.description,
        cwd: cmd.cwd,
        env: env,
        memory_budget: cmd.memory_budget,
    }

    with_memory : BuildCmd, U64 -> BuildCmd
    with_memory = |cmd, bytes| {
        depends_on_keys: cmd.depends_on_keys,
        program: cmd.program,
        args: cmd.args,
        description: cmd.description,
        cwd: cmd.cwd,
        env: cmd.env,
        memory_budget: bytes,
    }
}
