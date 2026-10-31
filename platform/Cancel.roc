## Cooperative cancellation token.
Cancel := {
    id : U64,
}.{
    from_id : U64 -> Cancel
    from_id = |id| {
        id: id,
    }

    to_id : Cancel -> U64
    to_id = |token| token.id
}
