const std = @import("std");
const builtin = @import("builtin");
const abi = @import("roc_platform_abi.zig");

const HostEnv = struct {
    gpa: std.heap.DebugAllocator(.{}),
    roc_env: abi.RocEnv,
    threaded: std.Io.Threaded,
};

extern fn roc_main(args: abi.RocList(abi.RocStr)) callconv(.c) i32;

var g_roc_host: ?*abi.RocHost = null;
var g_host_env: ?*HostEnv = null;
var g_environ: std.process.Environ = .empty;

// ---------------------------------------------------------------------------
// Hosted: run graph
// ---------------------------------------------------------------------------

fn hostedRunGraph(arg0: abi.HostRun_graphArgs) callconv(.c) abi.HostRun_graphResult {
    const max_memory: u64 = arg0.max_memory;
    const max_parallel_tasks: u64 = arg0.max_parallel;

    const roc_host = g_roc_host.?;
    defer arg0.decref(roc_host);

    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const roc_tasks = arg0.tasks.items();
    const zig_tasks = arena.alloc(ZigTask, roc_tasks.len) catch {
        return runGraphErr("oom allocating task list", roc_host);
    };

    for (roc_tasks, 0..) |t, i| {
        zig_tasks[i] = decodeTask(t, arena) catch {
            return runGraphErr("failed to decode task", roc_host);
        };
    }

    runZigGraph(zig_tasks, max_memory, max_parallel_tasks, arena) catch |err| {
        const msg = switch (err) {
            error.TaskFailed => "build task failed (see logs for task id / exit status)",
            error.CycleOrStuck => "dependency cycle or stuck graph (no ready tasks and none running)",
            error.TaskExceedsMemoryLimit => "a single task memory_budget exceeds max_memory even when run alone (see logs)",
            else => "build failed",
        };
        std.log.err("runZigGraph failed: {s} ({s})", .{ @errorName(err), msg });
        return runGraphErr(msg, roc_host);
    };

    return runGraphOk();
}

// ---------------------------------------------------------------------------
// Hosted: logging
// ---------------------------------------------------------------------------

fn hostedLogInfo(str: abi.RocStr) callconv(.c) void {
    const h = g_roc_host.?;
    defer str.decref(h);
    std.log.info("{s}", .{str.asSlice()});
}

fn hostedLogWarn(str: abi.RocStr) callconv(.c) void {
    const h = g_roc_host.?;
    defer str.decref(h);
    std.log.warn("{s}", .{str.asSlice()});
}

fn hostedLogError(str: abi.RocStr) callconv(.c) void {
    const h = g_roc_host.?;
    defer str.decref(h);
    std.log.err("{s}", .{str.asSlice()});
}

// ---------------------------------------------------------------------------
// Hosted stubs (required symbols from glue)
// ---------------------------------------------------------------------------

fn hostedCmdExec(arg0: abi.HostCmd_execArgs) callconv(.c) abi.HostCmd_execResult {
    const h = g_roc_host.?;
    defer arg0.decref(h);
    // TODO: implement single-command exec
    return .{
        .payload = .{ .err = .{
            .payload = .{ .cmd_err = abi.RocStr.fromSlice("cmd_exec not implemented", h) },
            .tag = .CmdErr,
        } },
        .tag = .Err,
    };
}

fn hostedFileReadBytes(arg0: abi.RocStr) callconv(.c) abi.HostFile_read_bytesResult {
    const h = g_roc_host.?;
    defer arg0.decref(h);
    return .{
        .payload = .{ .err = abi.RocStr.fromSlice("file_read_bytes not implemented", h) },
        .tag = .Err,
    };
}

fn hostedFileWriteBytes(arg0: abi.RocStr, arg1: abi.RocListWith(u8, false)) callconv(.c) abi.HostFile_write_bytesResult {
    const h = g_roc_host.?;
    defer arg0.decref(h);
    defer arg1.decref(h);
    return .{
        .payload = .{ .err = abi.RocStr.fromSlice("file_write_bytes not implemented", h) },
        .tag = .Err,
    };
}

fn hostedPathExists(arg0: abi.RocStr) callconv(.c) bool {
    const h = g_roc_host.?;
    defer arg0.decref(h);
    return false;
}

// ---------------------------------------------------------------------------
// Runtime symbols
// ---------------------------------------------------------------------------

fn hostAlloc(length: usize, alignment: usize) callconv(.c) ?*anyopaque {
    return abi.DefaultAllocators.rocAlloc(g_roc_host.?, length, alignment);
}
fn hostDealloc(ptr: *anyopaque, alignment: usize) callconv(.c) void {
    abi.DefaultAllocators.rocDealloc(g_roc_host.?, ptr, alignment);
}
fn hostRealloc(ptr: *anyopaque, new_length: usize, alignment: usize) callconv(.c) ?*anyopaque {
    return abi.DefaultAllocators.rocRealloc(g_roc_host.?, ptr, new_length, alignment);
}
fn hostDbg(bytes: [*]const u8, len: usize) callconv(.c) void {
    abi.DefaultHandlers.rocDbg(g_roc_host.?, bytes, len);
}
fn hostExpectFailed(bytes: [*]const u8, len: usize) callconv(.c) void {
    abi.DefaultHandlers.rocExpectFailed(g_roc_host.?, bytes, len);
}
fn hostCrashed(bytes: [*]const u8, len: usize) callconv(.c) void {
    abi.DefaultHandlers.rocCrashed(g_roc_host.?, bytes, len);
}

comptime {
    if (!builtin.is_test) {
        @export(&main, .{ .name = "main" });

        @export(&hostedRunGraph, .{ .name = "roc_build_run_graph", .visibility = .hidden });
        @export(&hostedLogInfo, .{ .name = "roc_log_info", .visibility = .hidden });
        @export(&hostedLogWarn, .{ .name = "roc_log_warn", .visibility = .hidden });
        @export(&hostedLogError, .{ .name = "roc_log_error", .visibility = .hidden });
        @export(&hostedCmdExec, .{ .name = "roc_cmd_exec", .visibility = .hidden });
        @export(&hostedFileReadBytes, .{ .name = "roc_file_read_bytes", .visibility = .hidden });
        @export(&hostedFileWriteBytes, .{ .name = "roc_file_write_bytes", .visibility = .hidden });
        @export(&hostedPathExists, .{ .name = "roc_path_exists", .visibility = .hidden });

        @export(&hostAlloc, .{ .name = "roc_alloc", .visibility = .hidden });
        @export(&hostDealloc, .{ .name = "roc_dealloc", .visibility = .hidden });
        @export(&hostRealloc, .{ .name = "roc_realloc", .visibility = .hidden });
        @export(&hostDbg, .{ .name = "roc_dbg", .visibility = .hidden });
        @export(&hostExpectFailed, .{ .name = "roc_expect_failed", .visibility = .hidden });
        @export(&hostCrashed, .{ .name = "roc_crashed", .visibility = .hidden });
    }
}

// ---------------------------------------------------------------------------
// Entry
// ---------------------------------------------------------------------------

fn main(argc: c_int, argv: [*][*:0]u8, envp: [*:null]?[*:0]const u8) callconv(.c) c_int {
    return platform_main(@intCast(argc), argv, envp);
}

fn platform_main(argc: usize, argv: [*][*:0]u8, envp: [*:null]?[*:0]const u8) c_int {
    var host_env = HostEnv{
        .gpa = .{},
        .roc_env = undefined,
        .threaded = undefined,
    };

    const gpa = host_env.gpa.allocator();

    // Build Environ from the OS envp (gives PATH, etc.)
    var env_count: usize = 0;
    while (envp[env_count] != null) : (env_count += 1) {}
    const env_block: std.process.Environ.Block = .{
        .slice = envp[0..env_count :null],
    };
    g_environ = .{ .block = env_block };

    host_env.threaded = .init(gpa, .{ .environ = g_environ });
    defer host_env.threaded.deinit();

    host_env.roc_env = .{
        .allocator = gpa,
        .roc_io = abi.RocIo.default(),
    };
    var roc_host = abi.makeRocHost(&host_env.roc_env);
    g_roc_host = &roc_host;
    g_host_env = &host_env;

    const args = buildStrArgsList(argc, argv, &roc_host);
    const code = roc_main(args);

    _ = host_env.gpa.deinit();
    return code;
}

fn buildStrArgsList(argc: usize, argv: [*][*:0]u8, roc_host: *abi.RocHost) abi.RocList(abi.RocStr) {
    if (argc == 0) return abi.RocList(abi.RocStr).empty();
    const list = abi.RocList(abi.RocStr).allocate(argc, roc_host);
    const ptr: [*]abi.RocStr = list.elements_ptr.?;
    for (0..argc) |i| {
        const c = argv[i];
        ptr[i] = abi.RocStr.fromSlice(c[0..std.mem.len(c)], roc_host);
    }
    return list;
}

// ---------------------------------------------------------------------------
// Graph result helpers
// ---------------------------------------------------------------------------

fn runGraphOk() abi.HostRun_graphResult {
    return .{
        .payload = .{ .ok = .{} },
        .tag = .Ok,
    };
}

fn runGraphErr(msg: []const u8, roc_host: *abi.RocHost) abi.HostRun_graphResult {
    return .{
        .payload = .{ .err = abi.RocStr.fromSlice(msg, roc_host) },
        .tag = .Err,
    };
}

// ---------------------------------------------------------------------------
// Task model + decode
// ---------------------------------------------------------------------------

const ZigTask = struct {
    id: u64,
    depends_on: []const u64,
    program: []const u8,
    args: []const []const u8,
    description: []const u8,
    cwd: []const u8,
    memory_budget: u64,
};

fn taskLabel(t: ZigTask) []const u8 {
    if (t.description.len > 0) return t.description;
    return t.program;
}

fn decodeTask(t: abi.HostRun_graphArg0Tasks, arena: std.mem.Allocator) !ZigTask {
    // Single-tag Action [Cmd(...)] is flattened to { program, args }.
    const program = try arena.dupe(u8, t.action.program.asSlice());
    const roc_args = t.action.args.items();
    const args = try arena.alloc([]const u8, roc_args.len);
    for (roc_args, 0..) |s, i| {
        args[i] = try arena.dupe(u8, s.asSlice());
    }

    return .{
        .id = t.id,
        .depends_on = try arena.dupe(u64, t.depends_on.items()),
        .program = program,
        .args = args,
        .description = try arena.dupe(u8, t.description.asSlice()),
        .cwd = try arena.dupe(u8, t.cwd.asSlice()),
        .memory_budget = t.memory_budget,
    };
}

// ---------------------------------------------------------------------------
// Scheduler (continuous queue + memory / parallel budgets)
// ---------------------------------------------------------------------------
//
// Ready tasks sit in a queue. We start as many as fit under max_memory and
// max_parallel. When a running task finishes we free its budget, unlock
// dependents, and try to start more.
//
// Hard errors only for:
//   * a single task whose memory_budget > max_memory (cannot ever run)
//   * dependency cycle / stuck graph
//   * a task process actually failing
//
// Transient "ready but does not fit right now" is NOT an error — we wait
// for a running task to finish and free resources.
//
// Zig 0.16 note: std.Thread.Mutex/Condition were removed (moved under
// std.Io). This scheduler avoids them by tracking active threads and
// joining the oldest when it needs a free slot.

const ActiveSlot = struct {
    thread: std.Thread,
    task_idx: usize,
};

fn effectiveLimit(configured: u64) u64 {
    if (configured == 0) return std.math.maxInt(u64);
    return configured;
}

fn warnBudgetHints(task: ZigTask, max_memory: u64) void {
    const budget = task.memory_budget;
    if (budget == 0) return;
    if (max_memory == 0) return;

    const pct_of_global = (budget * 100) / max_memory;

    if (pct_of_global >= 90) {
        std.log.warn(
            "task id={d} '{s}' memory_budget={d} is {d}% of max_memory={d} (near limit; may serialize heavily). Prefer ~50-75% of true need.",
            .{ task.id, taskLabel(task), budget, pct_of_global, max_memory },
        );
    } else if (pct_of_global < 5 and max_memory >= 1024 * 1024) {
        std.log.warn(
            "task id={d} '{s}' memory_budget={d} is only {d}% of max_memory={d} (massively under budget — consider tightening budgets). Prefer ~50-75% utilization of declared budget.",
            .{ task.id, taskLabel(task), budget, pct_of_global, max_memory },
        );
    }
}

fn runZigGraph(
    tasks: []const ZigTask,
    max_memory: u64,
    max_parallel: u64,
    allocator: std.mem.Allocator,
) !void {
    std.log.info(
        "runZigGraph: {d} tasks; max_memory={d} (0=unlimited) max_parallel={d} (0=unlimited)",
        .{ tasks.len, max_memory, max_parallel },
    );

    const n = tasks.len;
    if (n == 0) return;

    const mem_limit = effectiveLimit(max_memory);
    const par_limit = effectiveLimit(max_parallel);

    // Preflight: only fail if a single task can never fit, even alone.
    for (tasks) |t| {
        if (t.memory_budget != 0 and t.memory_budget > mem_limit) {
            std.log.err(
                "task id={d} '{s}' memory_budget={d} exceeds max_memory={d} even if run sequentially; constraint config: max_memory={d} max_parallel={d}",
                .{ t.id, taskLabel(t), t.memory_budget, max_memory, max_memory, max_parallel },
            );
            return error.TaskExceedsMemoryLimit;
        }
        warnBudgetHints(t, max_memory);
    }

    var remaining = try allocator.alloc(u32, n);
    defer allocator.free(remaining);

    var dependents = std.AutoHashMap(u64, std.ArrayList(usize)).init(allocator);
    defer {
        var it = dependents.valueIterator();
        while (it.next()) |list| list.deinit(allocator);
        dependents.deinit();
    }

    for (tasks, 0..) |t, i| {
        remaining[i] = @intCast(t.depends_on.len);
        for (t.depends_on) |dep| {
            const gop = try dependents.getOrPut(dep);
            if (!gop.found_existing) gop.value_ptr.* = .empty;
            try gop.value_ptr.append(allocator, i);
        }
    }

    var ready: std.ArrayList(usize) = .empty;
    defer ready.deinit(allocator);
    for (remaining, 0..) |r, i| {
        if (r == 0) try ready.append(allocator, i);
    }

    // Per-task success flag written by worker threads (each index written once).
    var results = try allocator.alloc(bool, n);
    defer allocator.free(results);
    @memset(results, false);

    var active: std.ArrayList(ActiveSlot) = .empty;
    defer {
        // On error paths, join any still-running workers so we don't leak threads.
        for (active.items) |slot| slot.thread.join();
        active.deinit(allocator);
    }

    var used_memory: u64 = 0;
    var done: usize = 0;

    while (done < n) {
        // Start every ready task that currently fits under both budgets.
        var i: usize = 0;
        while (i < ready.items.len) {
            const idx = ready.items[i];
            const task = tasks[idx];
            const budget = task.memory_budget;

            const fits_par = active.items.len < par_limit;
            const fits_mem = (budget == 0) or (used_memory + budget <= mem_limit);

            if (!(fits_par and fits_mem)) {
                i += 1;
                continue;
            }

            _ = ready.orderedRemove(i);
            if (budget != 0) used_memory += budget;

            std.log.info(
                "start id={d} '{s}' budget={d} (running={d}/{d} used_mem={d}/{d} ready_queued={d})",
                .{
                    task.id,
                    taskLabel(task),
                    budget,
                    active.items.len + 1,
                    par_limit,
                    used_memory,
                    mem_limit,
                    ready.items.len,
                },
            );

            const thread = try std.Thread.spawn(.{}, struct {
                fn run(t: ZigTask, out: *bool, alloc: std.mem.Allocator) void {
                    execCmd(t, alloc) catch {
                        out.* = false;
                        return;
                    };
                    out.* = true;
                }
            }.run, .{ task, &results[idx], allocator });

            try active.append(allocator, .{
                .thread = thread,
                .task_idx = idx,
            });
        }

        if (active.items.len == 0) {
            if (ready.items.len == 0) {
                std.log.err(
                    "graph stuck: done={d}/{d} ready=0 running=0 (likely dependency cycle). max_memory={d} max_parallel={d}",
                    .{ done, n, max_memory, max_parallel },
                );
                return error.CycleOrStuck;
            }
            // Ready work exists but nothing is running. Preflight guarantees
            // each task fits alone, so this should be unreachable.
            const idx = ready.items[0];
            const t = tasks[idx];
            std.log.err(
                "internal scheduler error: ready task id={d} '{s}' budget={d} did not start with running=0; max_memory={d} max_parallel={d}",
                .{ t.id, taskLabel(t), t.memory_budget, max_memory, max_parallel },
            );
            return error.TaskExceedsMemoryLimit;
        }

        // Wait for the oldest running task. (FIFO join — simple, no Mutex needed.)
        // Ready tasks that did not fit stay queued; after this join frees
        // budget/slots we loop and try to start them.
        const slot = active.orderedRemove(0);
        slot.thread.join();

        const idx = slot.task_idx;
        const task = tasks[idx];

        if (task.memory_budget != 0) {
            used_memory -= task.memory_budget;
        }

        if (!results[idx]) {
            std.log.err(
                "task FAILED id={d} '{s}' program={s} memory_budget={d} cwd={s} (constraint config: max_memory={d} max_parallel={d}; at failure: running={d} used_mem={d} ready_queued={d})",
                .{
                    task.id,
                    taskLabel(task),
                    task.program,
                    task.memory_budget,
                    task.cwd,
                    max_memory,
                    max_parallel,
                    active.items.len,
                    used_memory,
                    ready.items.len,
                },
            );
            return error.TaskFailed;
        }

        done += 1;
        std.log.info(
            "done  id={d} '{s}' (done={d}/{d} running={d} used_mem={d} ready_queued={d})",
            .{ task.id, taskLabel(task), done, n, active.items.len, used_memory, ready.items.len },
        );

        if (dependents.getPtr(task.id)) |deps| {
            for (deps.items) |di| {
                remaining[di] -= 1;
                if (remaining[di] == 0) {
                    try ready.append(allocator, di);
                }
            }
        }
    }
}

fn resolveOnPath(arena: std.mem.Allocator, prog: []const u8) ![:0]const u8 {
    if (std.mem.indexOfScalar(u8, prog, '/') != null) {
        return arena.dupeZ(u8, prog);
    }

    var path_val: ?[]const u8 = null;
    for (g_environ.block.slice) |opt_entry| {
        const entry = opt_entry orelse break;
        const s = std.mem.span(entry);
        if (std.mem.startsWith(u8, s, "PATH=")) {
            path_val = s["PATH=".len..];
            break;
        }
    }
    const path = path_val orelse return error.FileNotFound;

    var it = std.mem.splitScalar(u8, path, ':');
    while (it.next()) |dir| {
        if (dir.len == 0) continue;
        const candidate = try std.fmt.allocPrintSentinel(arena, "{s}/{s}", .{ dir, prog }, 0);
        // X_OK = 1
        if (std.c.access(candidate.ptr, 1) == 0) {
            return candidate;
        }
    }
    return error.FileNotFound;
}

fn execCmd(task: ZigTask, allocator: std.mem.Allocator) !void {
    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const prog_z = resolveOnPath(arena, task.program) catch {
        std.log.err(
            "program not found on PATH: task id={d} '{s}' program={s}",
            .{ task.id, taskLabel(task), task.program },
        );
        return error.TaskFailed;
    };

    const argv_z = try arena.allocSentinel(?[*:0]const u8, 1 + task.args.len, null);
    argv_z[0] = prog_z.ptr;
    for (task.args, 0..) |arg, i| {
        argv_z[i + 1] = try arena.dupeZ(u8, arg);
    }

    std.log.info("  $ {s}", .{prog_z});
    for (task.args) |a| std.log.info("      {s}", .{a});

    const pid = std.c.fork();
    if (pid < 0) {
        std.log.err(
            "fork failed for task id={d} '{s}' program={s}",
            .{ task.id, taskLabel(task), task.program },
        );
        return error.TaskFailed;
    }

    if (pid == 0) {
        if (task.cwd.len > 0) {
            const cwd_z = arena.dupeZ(u8, task.cwd) catch std.c._exit(127);
            if (std.c.chdir(cwd_z) != 0) std.c._exit(127);
        }

        const envp: [*:null]const ?[*:0]const u8 = g_environ.block.slice.ptr;
        _ = std.c.execve(prog_z.ptr, @ptrCast(argv_z.ptr), @ptrCast(envp));
        std.c._exit(127);
    }

    var status: c_int = 0;
    if (std.c.waitpid(pid, &status, 0) < 0) {
        std.log.err("waitpid failed for task id={d} '{s}'", .{ task.id, taskLabel(task) });
        return error.TaskFailed;
    }

    if ((status & 0x7f) == 0) {
        const code: u8 = @intCast((status >> 8) & 0xff);
        if (code != 0) {
            std.log.err(
                "task id={d} '{s}' exited with code {d} (program={s})",
                .{ task.id, taskLabel(task), code, task.program },
            );
            return error.TaskFailed;
        }
        return;
    }
    std.log.err(
        "task id={d} '{s}' terminated abnormally (status={d} program={s})",
        .{ task.id, taskLabel(task), status, task.program },
    );
    return error.TaskFailed;
}
