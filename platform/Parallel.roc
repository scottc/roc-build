import Host
import Work
import Cancel

## Pure / effect work composition with async vs concurrent vs parallel.
Parallel := [].{
    PureOpts : {
        prefer_parallel : Bool,
    }

    EffectOpts : {
        require_concurrency : Bool,
    }

    ParallelOpts : {
        min_workers : U64,
    }

    default_pure_opts : {} -> PureOpts
    default_pure_opts = |_| {
        prefer_parallel: True,
    }

    default_effect_opts : {} -> EffectOpts
    default_effect_opts = |_| {
        require_concurrency: False,
    }

    default_parallel_opts : {} -> ParallelOpts
    default_parallel_opts = |_| {
        min_workers: 0,
    }

    bool_to_u64 : Bool -> U64
    bool_to_u64 = |b| {
        if b {
            1
        } else {
            0
        }
    }

    # -----------------------------------------------------------------
    # Submit
    # -----------------------------------------------------------------

    submit_pure! :
        (input -> output),
        input,
        PureOpts
        => Try(Work, [SubmitErr(Str)])

    submit_pure! = |pure_fn, input, opts| {
        prefer = bool_to_u64(opts.prefer_parallel)
        match Host.parallel_submit_pure!(Box.box(pure_fn), Box.box(input), prefer) {
            Ok(id) => Try.Ok(Work.from_id(id))
            Err(msg) => Try.Err(SubmitErr(msg))
        }
    }

    submit_pure_default! :
        (input -> output),
        input
        => Try(Work, [SubmitErr(Str)])

    submit_pure_default! = |pure_fn, input|
        submit_pure!(pure_fn, input, default_pure_opts({}))

    submit_effect! :
        ({} => Try(ok, err)),
        EffectOpts
        => Try(Work, [SubmitErr(Str), ConcurrencyUnavailable])

    submit_effect! = |effect_thunk, opts| {
        require = bool_to_u64(opts.require_concurrency)

        boxed_thunk! : {} => Try(Box(ok), Box(err))
        boxed_thunk! = |_| {
            match effect_thunk({}) {
                Ok(v) => Try.Ok(Box.box(v))
                Err(e) => Try.Err(Box.box(e))
            }
        }

        match Host.parallel_submit_effect!(Box.box(boxed_thunk!), require) {
            Ok(id) => Try.Ok(Work.from_id(id))
            Err(ConcurrencyUnavailable) => Try.Err(ConcurrencyUnavailable)
            Err(SubmitErr(msg)) => Try.Err(SubmitErr(msg))
        }
    }

    submit_effect_default! :
        ({} => Try(ok, err))
        => Try(Work, [SubmitErr(Str), ConcurrencyUnavailable])

    submit_effect_default! = |effect_thunk|
        submit_effect!(effect_thunk, default_effect_opts({}))

    # -----------------------------------------------------------------
    # Await
    # -----------------------------------------------------------------

    ## Errors are tagged so the union stays well-formed with type vars.
    await! : Work => Try(ok, [Cancelled, WorkErr(err)])

    await! = |work| {
        match Host.parallel_await!(Work.to_id(work)) {
            Ok(boxed_ok) => Try.Ok(Box.unbox(boxed_ok))
            Err(Cancelled) => Try.Err(Cancelled)
            Err(WorkErr(boxed_err)) => Try.Err(WorkErr(Box.unbox(boxed_err)))
        }
    }

    await_all! : List(Work) => Try(List(ok), [Cancelled, WorkErr(err)])

    await_all! = |works| {
        len = List.len(works)
        await_all_help!(works, len, 0, [])
    }

    await_all_help! :
        List(Work),
        U64,
        U64,
        List(ok)
        => Try(List(ok), [Cancelled, WorkErr(err)])

    await_all_help! = |works, len, i, results| {
        if i >= len {
            Try.Ok(results)
        } else {
            match List.get(works, i) {
                Err(_) => Try.Err(Cancelled)
                Ok(w) => {
                    match await!(w) {
                        Ok(value) =>
                            await_all_help!(works, len, i + 1, List.append(results, value))
                        Err(e) => Try.Err(e)
                    }
                }
            }
        }
    }

    # -----------------------------------------------------------------
    # Compose
    # -----------------------------------------------------------------

    async2! : Work, Work => Try(Work, [SubmitErr(Str)])

    async2! = |wa, wb| {
        match Host.parallel_compose!(Work.to_id(wa), Work.to_id(wb), 0) {
            Ok(id) => Try.Ok(Work.from_id(id))
            Err(ConcurrencyUnavailable) =>
                Try.Err(SubmitErr("unexpected ConcurrencyUnavailable in async2"))
            Err(SubmitErr(msg)) => Try.Err(SubmitErr(msg))
        }
    }

    concurrent2! : Work, Work => Try(Work, [SubmitErr(Str), ConcurrencyUnavailable])

    concurrent2! = |wa, wb| {
        match Host.parallel_compose!(Work.to_id(wa), Work.to_id(wb), 1) {
            Ok(id) => Try.Ok(Work.from_id(id))
            Err(ConcurrencyUnavailable) => Try.Err(ConcurrencyUnavailable)
            Err(SubmitErr(msg)) => Try.Err(SubmitErr(msg))
        }
    }

    parallel2! :
        Work,
        Work,
        ParallelOpts
        => Try(Work, [SubmitErr(Str), ParallelismUnavailable])

    parallel2! = |wa, wb, opts| {
        match Host.parallel_compose_parallel!(
            Work.to_id(wa),
            Work.to_id(wb),
            opts.min_workers,
        ) {
            Ok(id) => Try.Ok(Work.from_id(id))
            Err(ParallelismUnavailable) => Try.Err(ParallelismUnavailable)
            Err(SubmitErr(msg)) => Try.Err(SubmitErr(msg))
        }
    }

    async_all! : List(Work) => Try(Work, [SubmitErr(Str)])

    async_all! = |works| {
        ids = List.map(works, Work.to_id)
        match Host.parallel_compose_all!(Box.box(ids), 0) {
            Ok(id) => Try.Ok(Work.from_id(id))
            Err(ConcurrencyUnavailable) =>
                Try.Err(SubmitErr("unexpected ConcurrencyUnavailable in async_all"))
            Err(SubmitErr(msg)) => Try.Err(SubmitErr(msg))
        }
    }

    concurrent_all! : List(Work) => Try(Work, [SubmitErr(Str), ConcurrencyUnavailable])

    concurrent_all! = |works| {
        ids = List.map(works, Work.to_id)
        match Host.parallel_compose_all!(Box.box(ids), 1) {
            Ok(id) => Try.Ok(Work.from_id(id))
            Err(ConcurrencyUnavailable) => Try.Err(ConcurrencyUnavailable)
            Err(SubmitErr(msg)) => Try.Err(SubmitErr(msg))
        }
    }

    parallel_all! :
        List(Work),
        ParallelOpts
        => Try(Work, [SubmitErr(Str), ParallelismUnavailable])

    parallel_all! = |works, opts| {
        ids = List.map(works, Work.to_id)
        match Host.parallel_compose_all_parallel!(Box.box(ids), opts.min_workers) {
            Ok(id) => Try.Ok(Work.from_id(id))
            Err(ParallelismUnavailable) => Try.Err(ParallelismUnavailable)
            Err(SubmitErr(msg)) => Try.Err(SubmitErr(msg))
        }
    }

    select2! : Work, Work => Try(Box(select_ok), Box(select_err))

    select2! = |wa, wb|
        Host.parallel_select2!(Work.to_id(wa), Work.to_id(wb))

    # -----------------------------------------------------------------
    # Groups / cancel
    # -----------------------------------------------------------------

    with_group! :
        (Cancel => Try(ok, err))
        => Try(ok, [Cancelled, WorkErr(err)])

    with_group! = |body| {
        match Host.parallel_group_begin!({}) {
            Ok(token_id) => {
                token = Cancel.from_id(token_id)
                result = body(token)
                Host.parallel_group_end!(token_id)
                match result {
                    Ok(v) => Try.Ok(v)
                    Err(e) => Try.Err(WorkErr(e))
                }
            }
            Err(Cancelled) => Try.Err(Cancelled)
            Err(GroupErr(_)) => Try.Err(Cancelled)
        }
    }

    cancel! : Cancel => {}

    cancel! = |token| {
        Host.parallel_cancel!(Cancel.to_id(token))
        {}
    }

    is_cancelled! : Cancel => Bool

    is_cancelled! = |token|
        Host.parallel_is_cancelled!(Cancel.to_id(token))

    # -----------------------------------------------------------------
    # pure_map!
    # -----------------------------------------------------------------

    pure_map! :
        List(input),
        (input -> output)
        => Try(List(output), [SubmitErr(Str), Cancelled, WorkErr(err)])

    pure_map! = |inputs, pure_fn|
        pure_map_submit!(inputs, pure_fn, List.len(inputs), 0, [])

    pure_map_submit! :
        List(input),
        (input -> output),
        U64,
        U64,
        List(Work)
        => Try(List(output), [SubmitErr(Str), Cancelled, WorkErr(err)])

    pure_map_submit! = |inputs, pure_fn, len, i, handles| {
        if i >= len {
            pure_map_finish!(handles)
        } else {
            match List.get(inputs, i) {
                Err(_) => Try.Err(SubmitErr("pure_map: index out of bounds"))
                Ok(item) => {
                    match submit_pure_default!(pure_fn, item) {
                        Ok(h) =>
                            pure_map_submit!(
                                inputs,
                                pure_fn,
                                len,
                                i + 1,
                                List.append(handles, h),
                            )
                        Err(e) => Try.Err(e)
                    }
                }
            }
        }
    }

    pure_map_finish! :
        List(Work)
        => Try(List(output), [SubmitErr(Str), Cancelled, WorkErr(err)])

    pure_map_finish! = |handles| {
        if List.len(handles) <= 1 {
            await_all!(handles)
        } else {
            match parallel_all!(handles, default_parallel_opts({})) {
                Ok(joined) => {
                    match await!(joined) {
                        Ok(list) => Try.Ok(list)
                        Err(Cancelled) => Try.Err(Cancelled)
                        Err(WorkErr(e)) => Try.Err(WorkErr(e))
                    }
                }
                Err(ParallelismUnavailable) => await_all!(handles)
                Err(SubmitErr(msg)) => Try.Err(SubmitErr(msg))
            }
        }
    }
}
