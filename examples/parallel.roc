app [main!] { pf: platform "../platform/main.roc" }

import pf.Log
import pf.Parallel
import pf.Work
import pf.Cancel

sum_chunk : { start : U64, end : U64 } -> U64
sum_chunk = |{ start, end }| {
    # trivial pure body for check; replace with a real fold later
    end - start
}

main! = |_args| {
    results = Parallel.pure_map!(
        [
            { start: 0, end: 1_000_000 },
            { start: 1_000_000, end: 2_000_000 },
        ],
        sum_chunk,
    )?

    h1 = Parallel.submit_pure_default!(sum_chunk, { start: 0, end: 100 })?
    h2 = Parallel.submit_pure_default!(sum_chunk, { start: 100, end: 200 })?
    joined = Parallel.parallel2!(h1, h2, Parallel.default_parallel_opts({}))?
    pair = Parallel.await!(joined)?

    _ = Parallel.with_group!(|token| {
        if Parallel.is_cancelled!(token) {
            Err(Cancelled)
        } else {
            Ok({})
        }
    })?

    Log.info!("results=${Str.inspect(results)} pair=${Str.inspect(pair)}")

    Ok({})
}
