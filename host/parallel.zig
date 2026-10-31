const std = @import("std");
const builtin = @import("builtin");

const abi = @import("roc_platform_abi.zig");

// ---------------------------------------------------------------------------
// Scheduler state
// ---------------------------------------------------------------------------

const WorkKind = enum { pure_done, effect_done, join, group };

const WorkEntry = struct {
    kind: WorkKind,
    cancelled: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    // For v0.1 pure path we run inline or on pool and store a boxed result pointer later.
    done: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    parent_group: ?u64 = null,
};

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

var works: std.ArrayList(WorkEntry) = .empty;
var works_mu: std.Thread.Mutex = .{};
var next_id: std.atomic.Value(u64) = std.atomic.Value(u64).init(1);

fn allocWork(kind: WorkKind, parent: ?u64) !u64 {
    works_mu.lock();
    defer works_mu.unlock();
    const id = next_id.fetchAdd(1, .monotonic);
    // id is 1-based index into list for simplicity in v0.1
    try works.append(allocator, .{
        .kind = kind,
        .parent_group = parent,
    });
    // Keep id == index+1 only if we never free slots; fine for rc1.
    _ = id;
    return works.items.len; // 1-based
}

fn getWork(id: u64) ?*WorkEntry {
    if (id == 0 or id > works.items.len) return null;
    return &works.items[id - 1];
}

// Optional: track active group for parentage (TLS or stack).
threadlocal var current_group: ?u64 = null;

// ---------------------------------------------------------------------------
// Hosted exports
// ---------------------------------------------------------------------------

/// Pure submit. v0.1: run callable later via await, or immediately on a worker.
/// Full Roc callable ABI needs glue helpers (call erased callable, box results).
/// Until those helpers are wired, return a work id and mark done with a dummy.
pub export fn roc_parallel_submit_pure(
    arg0: *abi.RocErasedCallable,
    arg1: *abi.RocBox,
    prefer_parallel: u64,
) callconv(.c) abi.HostParallel_submit_pureResult {
    _ = prefer_parallel;

    // Ownership: must decref arg0/arg1 exactly once unless moved into storage.
    // TODO: call platform decref helpers from glue:
    //   decrefErasedCallable(arg0, roc_host);
    //   decrefBox(arg1, roc_host);

    const id = allocWork(.pure_done, current_group) catch {
        // Err path must return owned Str — use your RocStr constructor from glue.
        return .{ .tag = 1, .payload = 0 };
    };

    // v0.1: do not invoke the Roc callable yet (needs stable call ABI).
    // Mark as completed empty job so await does not hang.
    if (getWork(id)) |w| {
        w.done.store(true, .release);
    }

    _ = arg0;
    _ = arg1;
    return .{ .tag = 0, .payload = id }; // Ok(id)
}

pub export fn roc_parallel_submit_effect(
    arg0: *abi.RocErasedCallable,
    require_concurrency: u64,
) callconv(.c) abi.HostParallel_submit_effectResult {
    if (require_concurrency != 0) {
        // Single-threaded host cannot guarantee concurrency:
        // return ConcurrencyUnavailable if you have no extra concurrency unit.
        // return .{ .tag = concurrency_unavailable_tag, .payload = 0 };
    }

    const id = allocWork(.effect_done, current_group) catch {
        return .{ .tag = 1, .payload = 0 }; // SubmitErr
    };
    if (getWork(id)) |w| w.done.store(true, .release);

    _ = arg0; // decrefErasedCallable when not stored
    return .{ .tag = 0, .payload = id };
}

fn emptyUnitBox() abi.RocBox {
    // Box of unit / zero-sized placeholder for v0.1 when no real payload yet.
    const host = rocHost();
    const data = abi.allocateBox(0, @alignOf(u8), false, host);
    return data;
}

pub export fn roc_parallel_await(id: u64) callconv(.c) abi.HostParallel_awaitResult {
    const w = getWork(id) orelse {
        return .{ .tag = abi.HostParallel_awaitResultTag.Err, .payload = .{ .cancelled = .{} } };
    };
    if (w.cancelled.load(.acquire)) {
        return .{ .tag = abi.HostParallel_awaitResultTag.Err, .payload = .{ .cancelled = .{} } };
    }
    // Spin/wait until done (v0.1). Real host should park the Roc continuation.
    while (!w.done.load(.acquire)) {
        std.Thread.yield() catch {};
        if (w.cancelled.load(.acquire)) {
            return .{ .tag = abi.HostParallel_awaitResultTag.Err, .payload = .{ .cancelled = .{} } };
        }
    }

    const box = w.result_box orelse emptyUnitBox();
    w.result_box = null;

    // Ok(Box(...)) — must return an owned Box matching rigid ok type.
    // Without a real payload, pure_map/await will not type-check at runtime meaningfully.
    // Wire Box from glue once call results exist.
    return .{ .tag = abi.HostParallel_awaitResultTag.Ok, .payload = .{ .ok = box } };
}

pub export fn roc_parallel_compose(a: u64, b: u64, mode: u64) callconv(.c) abi.HostParallel_submit_effectResult {
    _ = a;
    _ = b;
    if (mode == 1) {
        // concurrent required — fail on hosts without concurrency unit if desired
    }
    const id = allocWork(.join, current_group) catch {
        return .{ .tag = 1, .payload = 0 };
    };
    if (getWork(id)) |w| w.done.store(true, .release);
    return .{ .tag = 0, .payload = id };
}

pub export fn roc_parallel_compose_parallel(a: u64, b: u64, min_workers: u64) callconv(.c) abi.HostParallel_compose_parallelResult {
    _ = min_workers;
    return roc_parallel_compose(a, b, 0);
}

pub export fn roc_parallel_compose_all(list: *abi.RocListWith(u64, false), mode: u64) callconv(.c) abi.HostParallel_compose_parallelResult {
    _ = list; // decref boxed list when not retained
    _ = mode;
    const id = allocWork(.join, current_group) catch {
        return .{ .tag = 1, .payload = 0 };
    };
    if (getWork(id)) |w| w.done.store(true, .release);
    return .{ .tag = 0, .payload = id };
}

pub export fn roc_parallel_compose_all_parallel(list: *abi.RocListWith(u64, false), min_workers: u64) callconv(.c) abi.HostParallel_compose_parallelResult {
    _ = min_workers;
    return roc_parallel_compose_all(list, 0);
}

pub export fn roc_parallel_select2(a: u64, b: u64) callconv(.c) abi.HostParallel_select2Result {
    _ = a;
    _ = b;
    return .{ .tag = abi.HostParallel_select2ResultTag.Err, .payload = .{} };
}

pub export fn roc_parallel_group_begin() callconv(.c) abi.HostParallel_group_beginResult {
    const id = allocWork(.group, null) catch {
        return .{ .tag = 1, .payload = 0 };
    };
    current_group = id;
    return .{ .tag = 0, .payload = id };
}

pub export fn roc_parallel_group_end(id: u64) callconv(.c) void {
    if (current_group == id) current_group = null;
}

pub export fn roc_parallel_cancel(id: u64) callconv(.c) void {
    works_mu.lock();
    defer works_mu.unlock();
    if (getWork(id)) |w| {
        w.cancelled.store(true, .release);
    }
    // Also cancel children with parent_group == id (v0.1 scan).
    for (works.items) |*entry| {
        if (entry.parent_group == id) {
            entry.cancelled.store(true, .release);
        }
    }
}

pub export fn roc_parallel_is_cancelled(id: u64) callconv(.c) bool {
    const w = getWork(id) orelse return true;
    return w.cancelled.load(.acquire);
}
