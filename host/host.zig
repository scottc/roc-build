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
    const roc_host = g_roc_host.?;
    defer arg0.decref(roc_host);

    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const roc_tasks = arg0.tasks.items();
    const zig_tasks = arena.alloc(ZigTask, roc_tasks.len) catch {
        return runGraphErr("oom", roc_host);
    };

    for (roc_tasks, 0..) |t, i| {
        zig_tasks[i] = decodeTask(t, arena) catch {
            return runGraphErr("failed to decode task", roc_host);
        };
    }

    runZigGraph(zig_tasks, arena) catch |err| {
        std.log.err("runZigGraph failed: {s}", .{@errorName(err)});
        return runGraphErr(switch (err) {
            error.TaskFailed => "build task failed",
            error.CycleOrStuck => "dependency cycle or stuck graph",
            else => "build failed",
        }, roc_host);
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
    // const process_environ: std.process.Environ = .{ .block = env_block };
    // host_env.threaded = .init(gpa, .{ .environ = process_environ });
    // ... rest unchanged
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
};

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
    };
}

// ---------------------------------------------------------------------------
// Scheduler (sequential topological)
// ---------------------------------------------------------------------------

fn runZigGraph(tasks: []const ZigTask, allocator: std.mem.Allocator) !void {
    const n = tasks.len;
    if (n == 0) return;

    var remaining = try allocator.alloc(u32, n);
    defer allocator.free(remaining);

    var id_to_index = std.AutoHashMap(u64, usize).init(allocator);
    defer id_to_index.deinit();

    for (tasks, 0..) |t, i| {
        try id_to_index.put(t.id, i);
        remaining[i] = @intCast(t.depends_on.len);
    }

    var dependents = std.AutoHashMap(u64, std.ArrayList(usize)).init(allocator);
    defer {
        var it = dependents.valueIterator();
        while (it.next()) |list| list.deinit(allocator);
        dependents.deinit();
    }

    for (tasks, 0..) |t, i| {
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

    var done: usize = 0;
    const WorkerResult = struct {
        ok: bool = false,
    };

    while (done < n) {
        if (ready.items.len == 0) return error.CycleOrStuck;

        // Run this whole ready wave in parallel
        const wave = try allocator.dupe(usize, ready.items);
        defer allocator.free(wave);
        ready.clearRetainingCapacity();

        var results = try allocator.alloc(WorkerResult, wave.len);
        defer allocator.free(results);
        @memset(results, .{});

        const Worker = struct {
            fn run(task: ZigTask, out: *WorkerResult, alloc: std.mem.Allocator) void {
                execCmd(task, alloc) catch {
                    out.ok = false;
                    return;
                };
                out.ok = true;
            }
        };

        var threads = try allocator.alloc(?std.Thread, wave.len);
        defer allocator.free(threads);
        @memset(threads, null);

        std.log.info("wave: {d} tasks in parallel", .{wave.len});

        for (wave, 0..) |idx, wi| {
            const task = tasks[idx];
            const label = if (task.description.len > 0) task.description else "(task)";
            std.log.info("start {s} (id={d})", .{ label, task.id });
            threads[wi] = try std.Thread.spawn(.{}, Worker.run, .{ task, &results[wi], allocator });
        }

        for (threads) |maybe_t| {
            if (maybe_t) |t| t.join();
        }

        for (wave, 0..) |idx, wi| {
            if (!results[wi].ok) return error.TaskFailed;

            const task = tasks[idx];
            done += 1;
            const label = if (task.description.len > 0) task.description else "(task)";
            std.log.info("done  {s}", .{label});

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
        std.log.err("program not found on PATH: {s}", .{task.program});
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
        std.log.err("fork failed for {s}", .{task.program});
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
        std.log.err("waitpid failed for task {d}", .{task.id});
        return error.TaskFailed;
    }

    if ((status & 0x7f) == 0) {
        const code: u8 = @intCast((status >> 8) & 0xff);
        if (code != 0) {
            std.log.err("task {d} exited {d}", .{ task.id, code });
            return error.TaskFailed;
        }
        return;
    }
    std.log.err("task {d} terminated abnormally (status={d})", .{ task.id, status });
    return error.TaskFailed;
}
