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

    Task : {
        id : TaskId,
        depends_on : List(TaskId),
        inputs : List(Str),
        outputs : List(Str),
        action : Action,
        description : Str,
        cwd : Str,
        env : List((Str, Str)),
    }

    BuildGraph : {
        tasks : List(Task),
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
}
