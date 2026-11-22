const std = @import("std");
const builtin = @import("builtin");
const abi = @import("roc_platform_abi.zig");

// Set by host.zig after makeRocHost (avoids circular import).
pub var roc_host_ptr: ?*abi.RocHost = null;

fn rocHost() ?*abi.RocHost {
    return roc_host_ptr;
}

// ---------------------------------------------------------------------------
// Scheduler state (v0.1 stub — no real callable execution yet)
// ---------------------------------------------------------------------------

const WorkKind = enum { pure_done, effect_done, join, group };

const WorkEntry = struct {
    kind: WorkKind,
    cancelled: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    done: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    parent_group: ?u64 = null,
    result_box: ?abi.RocBox = null,
};

const allocator = std.heap.page_allocator;

var works: std.ArrayList(WorkEntry) = .empty;

// Zig 0.17: std.Thread.Mutex is gone — simple spinlock is enough for v0.1.
var works_locked: std.atomic.Value(bool) = std.atomic.Value(bool).init(false);

fn worksLock() void {
    while (works_locked.swap(true, .acquire)) {
        std.atomic.spinLoopHint();
    }
}
fn worksUnlock() void {
    works_locked.store(false, .release);
}

var next_id: std.atomic.Value(u64) = std.atomic.Value(u64).init(1);

fn allocWork(kind: WorkKind, parent: ?u64) !u64 {
    worksLock();
    defer worksUnlock();
    _ = next_id.fetchAdd(1, .monotonic);
    try works.append(allocator, .{
        .kind = kind,
        .parent_group = parent,
    });
    return works.items.len; // 1-based id
}

fn getWork(id: u64) ?*WorkEntry {
    if (id == 0 or id > works.items.len) return null;
    return &works.items[id - 1];
}

threadlocal var current_group: ?u64 = null;

// ---------------------------------------------------------------------------
// Result helpers matching RC1 glue
// ---------------------------------------------------------------------------

fn submitPureOk(id: u64) abi.HostParallel_submit_pureResult {
    return .{ .tag = .Ok, .payload = .{ .ok = id } };
}

fn submitPureErr(msg: []const u8) abi.HostParallel_submit_pureResult {
    const h = rocHost() orelse {
        return .{ .tag = .Err, .payload = .{ .err = abi.RocStr.empty() } };
    };
    return .{ .tag = .Err, .payload = .{ .err = abi.RocStr.fromSlice(msg, h) } };
}

fn submitEffectOk(id: u64) abi.HostParallel_submit_effectResult {
    return .{ .tag = .Ok, .payload = .{ .ok = id } };
}

fn submitEffectSubmitErr(msg: []const u8) abi.HostParallel_submit_effectResult {
    const h = rocHost() orelse {
        return .{
            .tag = .Err,
            .payload = .{ .err = .{
                .tag = .SubmitErr,
                .payload = .{ .submit_err = abi.RocStr.empty() },
            } },
        };
    };
    return .{
        .tag = .Err,
        .payload = .{ .err = .{
            .tag = .SubmitErr,
            .payload = .{ .submit_err = abi.RocStr.fromSlice(msg, h) },
        } },
    };
}

fn submitEffectConcurrencyUnavailable() abi.HostParallel_submit_effectResult {
    return .{
        .tag = .Err,
        .payload = .{ .err = .{
            .tag = .ConcurrencyUnavailable,
            .payload = .{ .concurrency_unavailable = .{} },
        } },
    };
}

fn composeParallelOk(id: u64) abi.HostParallel_compose_parallelResult {
    return .{ .tag = .Ok, .payload = .{ .ok = id } };
}

fn composeParallelSubmitErr(msg: []const u8) abi.HostParallel_compose_parallelResult {
    const h = rocHost() orelse {
        return .{
            .tag = .Err,
            .payload = .{ .err = .{
                .tag = .SubmitErr,
                .payload = .{ .submit_err = abi.RocStr.empty() },
            } },
        };
    };
    return .{
        .tag = .Err,
        .payload = .{ .err = .{
            .tag = .SubmitErr,
            .payload = .{ .submit_err = abi.RocStr.fromSlice(msg, h) },
        } },
    };
}

fn awaitCancelled() abi.HostParallel_awaitResult {
    return .{
        .tag = .Err,
        .payload = .{ .err = .{
            .tag = .Cancelled,
            .payload = .{ .cancelled = .{} },
        } },
    };
}

fn awaitOk(box: abi.RocBox) abi.HostParallel_awaitResult {
    return .{ .tag = .Ok, .payload = .{ .ok = box } };
}

fn emptyUnitBox() abi.RocBox {
    const h = rocHost() orelse return null;
    return abi.allocateBox(0, @alignOf(u8), false, h);
}

fn groupBeginOk(id: u64) abi.HostParallel_group_beginResult {
    return .{ .tag = .Ok, .payload = .{ .ok = id } };
}

fn groupBeginErr(msg: []const u8) abi.HostParallel_group_beginResult {
    const h = rocHost() orelse {
        return .{
            .tag = .Err,
            .payload = .{ .err = .{
                .tag = .GroupErr,
                .payload = .{ .group_err = abi.RocStr.empty() },
            } },
        };
    };
    return .{
        .tag = .Err,
        .payload = .{ .err = .{
            .tag = .GroupErr,
            .payload = .{ .group_err = abi.RocStr.fromSlice(msg, h) },
        } },
    };
}

// ---------------------------------------------------------------------------
// Hosted exports
// ---------------------------------------------------------------------------

pub export fn roc_parallel_submit_pure(
    arg0: abi.RocErasedCallable,
    arg1: abi.RocBox,
    prefer_parallel: u64,
) callconv(.c) abi.HostParallel_submit_pureResult {
    _ = prefer_parallel;

    // v0.1: do not retain callables; drop if we have a host.
    if (rocHost()) |h| {
        abi.decrefErasedCallable(arg0, h);
        // arg1 is opaque Box(rigid) — only Roc can fully release; drop spine if possible.
        abi.decrefBox(arg1, h);
    }

    const id = allocWork(.pure_done, current_group) catch {
        return submitPureErr("oom allocating work");
    };
    if (getWork(id)) |w| {
        w.done.store(true, .release);
    }
    return submitPureOk(id);
}

pub export fn roc_parallel_submit_effect(
    arg0: abi.RocErasedCallable,
    require_concurrency: u64,
) callconv(.c) abi.HostParallel_submit_effectResult {
    if (require_concurrency != 0) {
        // Single-threaded stub cannot guarantee concurrency.
        if (rocHost()) |h| abi.decrefErasedCallable(arg0, h);
        return submitEffectConcurrencyUnavailable();
    }

    if (rocHost()) |h| abi.decrefErasedCallable(arg0, h);

    const id = allocWork(.effect_done, current_group) catch {
        return submitEffectSubmitErr("oom allocating work");
    };
    if (getWork(id)) |w| w.done.store(true, .release);
    return submitEffectOk(id);
}

pub export fn roc_parallel_await(id: u64) callconv(.c) abi.HostParallel_awaitResult {
    const w = getWork(id) orelse return awaitCancelled();
    if (w.cancelled.load(.acquire)) return awaitCancelled();

    while (!w.done.load(.acquire)) {
        std.Thread.yield() catch {};
        if (w.cancelled.load(.acquire)) return awaitCancelled();
    }

    const box = w.result_box orelse emptyUnitBox();
    w.result_box = null;
    return awaitOk(box);
}

pub export fn roc_parallel_compose(a: u64, b: u64, mode: u64) callconv(.c) abi.HostParallel_submit_effectResult {
    _ = a;
    _ = b;
    if (mode == 1) {
        return submitEffectConcurrencyUnavailable();
    }
    const id = allocWork(.join, current_group) catch {
        return submitEffectSubmitErr("oom allocating work");
    };
    if (getWork(id)) |w| w.done.store(true, .release);
    return submitEffectOk(id);
}

pub export fn roc_parallel_compose_parallel(a: u64, b: u64, min_workers: u64) callconv(.c) abi.HostParallel_compose_parallelResult {
    _ = a;
    _ = b;
    _ = min_workers;
    const id = allocWork(.join, current_group) catch {
        return composeParallelSubmitErr("oom allocating work");
    };
    if (getWork(id)) |w| w.done.store(true, .release);
    return composeParallelOk(id);
}

pub export fn roc_parallel_compose_all(
    list: *abi.RocListWith(u64, false),
    mode: u64,
) callconv(.c) abi.HostParallel_submit_effectResult {
    if (rocHost()) |h| {
        // Owned Box(List(U64)) — release as documented in glue.
        abi.decrefBoxWith(
            @ptrCast(list),
            @alignOf(abi.RocListWith(u64, false)),
            true,
            null, // list spine only is enough for stub; elements are non-refcounted u64
            h,
        );
    }
    _ = mode;
    const id = allocWork(.join, current_group) catch {
        return submitEffectSubmitErr("oom allocating work");
    };
    if (getWork(id)) |w| w.done.store(true, .release);
    return submitEffectOk(id);
}

pub export fn roc_parallel_compose_all_parallel(
    list: *abi.RocListWith(u64, false),
    min_workers: u64,
) callconv(.c) abi.HostParallel_compose_parallelResult {
    if (rocHost()) |h| {
        abi.decrefBoxWith(
            @ptrCast(list),
            @alignOf(abi.RocListWith(u64, false)),
            true,
            null,
            h,
        );
    }
    _ = min_workers;
    const id = allocWork(.join, current_group) catch {
        return composeParallelSubmitErr("oom allocating work");
    };
    if (getWork(id)) |w| w.done.store(true, .release);
    return composeParallelOk(id);
}

pub export fn roc_parallel_select2(a: u64, b: u64) callconv(.c) abi.HostParallel_select2Result {
    _ = a;
    _ = b;
    // v0.1: no real select — return Err with empty unit box payload.
    return .{
        .tag = .Err,
        .payload = .{ .err = emptyUnitBox() },
    };
}

pub export fn roc_parallel_group_begin() callconv(.c) abi.HostParallel_group_beginResult {
    const id = allocWork(.group, null) catch {
        return groupBeginErr("oom allocating group");
    };
    current_group = id;
    return groupBeginOk(id);
}

pub export fn roc_parallel_group_end(id: u64) callconv(.c) void {
    if (current_group == id) current_group = null;
}

pub export fn roc_parallel_cancel(id: u64) callconv(.c) void {
    worksLock();
    defer worksUnlock();
    if (getWork(id)) |w| {
        w.cancelled.store(true, .release);
    }
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
