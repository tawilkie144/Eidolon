const std = @import("std");

const modules: [1][]const u8 = .{"core"};

const targets = [_]std.Target.Query{
    .{
        .cpu_arch = .x86_64,
        .os_tag = .linux,
        .abi = .gnu,
    },
    .{
        .cpu_arch = .x86_64,
        .os_tag = .windows,
    },
};

pub fn build(b: *std.Build) !void {
    const optimize_opts = b.standardOptimizeOption(.{});
    const target_windows = b.option(bool, "windows", "Build for Windows") orelse false;
    const target: std.Target.Query = if (target_windows)
        targets[1]
    else
        targets[0];

    const include_realtime_tests = b.option(bool, "realtimeTests", "Include realtime tests") orelse false;

    const exe = b.addExecutable(.{
        .name = "Eidolon",
        .root_source_file = b.path("src/main.zig"),
        .target = b.resolveTargetQuery(target),
        .optimize = optimize_opts,
    });
    const target_output = b.addInstallArtifact(exe, .{
        .dest_dir = .{
            .override = .{
                .custom = try target.zigTriple(b.allocator),
            },
        },
    });

    b.getInstallStep().dependOn(&target_output.step);

    const run_test_step = b.step("test", "Run unit tests");
    {
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        defer _ = gpa.deinit();
        const allocator = gpa.allocator();

        const root_path = try std.fs.realpathAlloc(allocator, ".");
        defer allocator.free(root_path);

        for (modules) |module_name| {
            const mod_name = try std.fmt.allocPrint(allocator, "Eidolon_{s}", .{module_name});
            defer allocator.free(mod_name);
            const mod_file = try std.fmt.allocPrint(allocator, "src/{s}/{s}.zig", .{ module_name, module_name });
            defer allocator.free(mod_file);
            const mod = b.addModule(mod_name, .{
                .root_source_file = b.path(mod_file),
            });
            exe.root_module.addImport(mod_name, mod);

            const tests_dir_name = try std.fmt.allocPrint(allocator, "./src/tests/{s}", .{module_name});
            defer allocator.free(tests_dir_name);
            const tests_path = try std.fs.realpathAlloc(allocator, tests_dir_name);
            defer allocator.free(tests_path);
            var tests_dir = try std.fs.openDirAbsolute(tests_path, .{ .iterate = true });
            defer tests_dir.close();

            var walker = try tests_dir.walk(allocator);
            defer walker.deinit();
            while (try walker.next()) |entry| {
                if (entry.kind == .directory) continue;
                if (!std.mem.endsWith(u8, entry.basename, "_tests.zig")) continue;
                if (!include_realtime_tests and std.mem.endsWith(u8, entry.basename, "_realtime_tests.zig")) continue;
                var paths = [_][]const u8{ tests_path, entry.path };
                const test_file_path = try std.fs.path.join(allocator, &paths);
                defer allocator.free(test_file_path);
                const test_file_relative_path = try std.fs.path.relative(allocator, root_path, test_file_path);
                defer allocator.free(test_file_relative_path);
                const mod_test = b.addTest(.{
                    .root_source_file = b.path(test_file_relative_path),
                });
                mod_test.root_module.addImport(mod_name, mod);
                const run_test = b.addRunArtifact(mod_test);
                run_test_step.dependOn(&run_test.step);
            }
        }
    }

    const run_exe = b.addRunArtifact(exe);
    const run_step = b.step("run", "Run the application");
    run_step.dependOn(&run_exe.step);
}
