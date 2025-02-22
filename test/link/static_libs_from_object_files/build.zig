const std = @import("std");
const builtin = @import("builtin");

const Build = std.Build;
const LazyPath = Build.LazyPath;
const Step = Build.Step;
const Run = Step.Run;
const WriteFile = Step.WriteFile;

pub fn build(b: *Build) void {
    const nb_files = b.option(u32, "nb_files", "Number of c files to generate.") orelse 10;

    const test_step = b.step("test", "Test it");
    b.default_step = test_step;

    // generate c files
    const files = b.allocator.alloc(LazyPath, nb_files) catch unreachable;
    defer b.allocator.free(files);
    {
        for (files[0 .. nb_files - 1], 1..nb_files) |*file, i| {
            const wf = WriteFile.create(b);
            file.* = wf.add(b.fmt("src_{}.c", .{i}), b.fmt(
                \\extern int foo_0();
                \\extern int bar_{}();
                \\extern int one_{};
                \\int one_{} = 1;
                \\int foo_{}() {{ return one_{} + foo_0(); }}
                \\int bar_{}() {{ return bar_{}(); }}
            , .{ i - 1, i - 1, i, i, i - 1, i, i - 1 }));
        }

        {
            const wf = WriteFile.create(b);
            files[nb_files - 1] = wf.add("src_last.c", b.fmt(
                \\extern int foo_0();
                \\extern int bar_{}();
                \\extern int one_{};
                \\int foo_last() {{ return one_{} + foo_0(); }}
                \\int bar_last() {{ return bar_{}(); }}
            , .{ nb_files - 1, nb_files - 1, nb_files - 1, nb_files - 1 }));
        }
    }

    add(b, test_step, files, .Debug);
    add(b, test_step, files, .ReleaseSafe);
    add(b, test_step, files, .ReleaseSmall);
    add(b, test_step, files, .ReleaseFast);
}

fn add(b: *Build, test_step: *Step, files: []const LazyPath, optimize: std.builtin.OptimizeMode) void {
    const flags = [_][]const u8{
        "-Wall",
        "-std=c11",
    };

    // all files at once
    {
        const exe = b.addExecutable(.{
            .name = "test1",
            .root_module = b.createModule(.{
                .root_source_file = b.path("main.zig"),
                .optimize = optimize,
                .target = b.graph.host,
            }),
        });

        for (files) |file| {
            exe.root_module.addCSourceFile(.{ .file = file, .flags = &flags });
        }

        const run_cmd = b.addRunArtifact(exe);
        run_cmd.skip_foreign_checks = true;
        run_cmd.expectExitCode(0);

        test_step.dependOn(&run_cmd.step);
    }

    // using static librairies
    {
        const mod_a = b.createModule(.{ .target = b.graph.host, .optimize = optimize });
        const mod_b = b.createModule(.{ .target = b.graph.host, .optimize = optimize });

        for (files, 1..) |file, i| {
            const mod = if (i & 1 == 0) mod_a else mod_b;
            mod.addCSourceFile(.{ .file = file, .flags = &flags });
        }

        const lib_a = b.addLibrary(.{
            .linkage = .static,
            .name = "test2_a",
            .root_module = mod_a,
        });
        const lib_b = b.addLibrary(.{
            .linkage = .static,
            .name = "test2_b",
            .root_module = mod_b,
        });

        const exe = b.addExecutable(.{
            .name = "test2",
            .root_module = b.createModule(.{
                .root_source_file = b.path("main.zig"),
                .target = b.graph.host,
                .optimize = optimize,
            }),
        });
        exe.root_module.linkLibrary(lib_a);
        exe.root_module.linkLibrary(lib_b);

        const run_cmd = b.addRunArtifact(exe);
        run_cmd.skip_foreign_checks = true;
        run_cmd.expectExitCode(0);

        test_step.dependOn(&run_cmd.step);
    }

    // using static librairies and object files
    {
        const mod_a = b.createModule(.{ .target = b.graph.host, .optimize = optimize });
        const mod_b = b.createModule(.{ .target = b.graph.host, .optimize = optimize });

        for (files, 1..) |file, i| {
            const obj_mod = b.createModule(.{ .target = b.graph.host, .optimize = optimize });
            obj_mod.addCSourceFile(.{ .file = file, .flags = &flags });

            const obj = b.addObject(.{
                .name = b.fmt("obj_{}", .{i}),
                .root_module = obj_mod,
            });

            const lib_mod = if (i & 1 == 0) mod_a else mod_b;
            lib_mod.addObject(obj);
        }

        const lib_a = b.addLibrary(.{
            .linkage = .static,
            .name = "test3_a",
            .root_module = mod_a,
        });
        const lib_b = b.addLibrary(.{
            .linkage = .static,
            .name = "test3_b",
            .root_module = mod_b,
        });

        const exe = b.addExecutable(.{
            .name = "test3",
            .root_module = b.createModule(.{
                .root_source_file = b.path("main.zig"),
                .target = b.graph.host,
                .optimize = optimize,
            }),
        });
        exe.root_module.linkLibrary(lib_a);
        exe.root_module.linkLibrary(lib_b);

        const run_cmd = b.addRunArtifact(exe);
        run_cmd.skip_foreign_checks = true;
        run_cmd.expectExitCode(0);

        test_step.dependOn(&run_cmd.step);
    }
}
