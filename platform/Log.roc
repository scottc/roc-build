import Host

Log := [].{
    info! : Str => {}
    info! = |msg| Host.log_info!(msg)

    warn! : Str => {}
    warn! = |msg| Host.log_warn!(msg)

    error! : Str => {}
    error! = |msg| Host.log_error!(msg)
}
