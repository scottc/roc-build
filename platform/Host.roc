## Internal hosted-effect boundary. Apps should use Build / Log, not Host.
Host := [].{
    # Data exchanged with the host (ABI-facing — keep simple)
    TaskId : U64

    CmdSpec : {
        program : Str,
        args : List(Str),
    }

    Action : [
        Cmd(CmdSpec),
    ]

    # In Host
    Task : {
        id : TaskId,
        depends_on : List(TaskId),
        inputs : List(Str),      # keep for future hashing/caching
        outputs : List(Str),
        action : Action,
        description : Str,
        cwd : Str,
        env : List((Str, Str)),
        memory_budget : U64,     # NEW
    }

    BuildGraph : {
        tasks : List(Task),
        max_memory : U64,    # 0 = unlimited (not recommended)
        max_parallel : U64,  # 0 = unlimited
    }

    # Hosted effects
    run_graph! : BuildGraph => Try({}, [BuildFailed(Str)])

    log_info! : Str => {}
    log_warn! : Str => {}
    log_error! : Str => {}

    cmd_exec! : CmdSpec => Try({}, [NonZeroExit(I32), CmdErr(Str)])

    file_read_bytes! : Str => Try(List(U8), [IoErr(Str)])
    file_write_bytes! : Str, List(U8) => Try({}, [IoErr(Str)])
    path_exists! : Str => Bool


    ## prefer_parallel: 0 | 1
    parallel_submit_pure! :
        Box(input -> output),
        Box(input),
        U64
        => Try(U64, Str)

    ## require_concurrency: 0 | 1
    parallel_submit_effect! :
        Box({} => Try(Box(ok), Box(err))),
        U64
        => Try(U64, [SubmitErr(Str), ConcurrencyUnavailable])

    parallel_await! :
        U64
        => Try(Box(ok), [Cancelled, WorkErr(Box(err))])

    ## mode: 0 = async, 1 = concurrent
    parallel_compose! :
        U64,
        U64,
        U64
        => Try(U64, [SubmitErr(Str), ConcurrencyUnavailable])

    parallel_compose_parallel! :
        U64,
        U64,
        U64
        => Try(U64, [SubmitErr(Str), ParallelismUnavailable])

    parallel_compose_all! :
        Box(List(U64)),
        U64
        => Try(U64, [SubmitErr(Str), ConcurrencyUnavailable])

    parallel_compose_all_parallel! :
        Box(List(U64)),
        U64
        => Try(U64, [SubmitErr(Str), ParallelismUnavailable])

    parallel_select2! :
        U64,
        U64
        => Try(Box(select_ok), Box(select_err))

    parallel_group_begin! : {} => Try(U64, [Cancelled, GroupErr(Str)])

    parallel_group_end! : U64 => {}

    parallel_cancel! : U64 => {}

    parallel_is_cancelled! : U64 => Bool

}
