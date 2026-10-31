## Opaque work handle. Host stores the real job behind `id`.
Work := {
    id : U64,
}.{
    from_id : U64 -> Work
    from_id = |id| {
        id: id,
    }

    to_id : Work -> U64
    to_id = |work| work.id
}
