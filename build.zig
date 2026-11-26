const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const version = getVersion(b);

    // `-Dstrip`: no debug info, as the release workflow ships it. It also makes
    // the Mach-O build reproducible: the debug map carries each object file's
    // mtime, and the linker writes it into the binary.
    const strip = b.option(bool, "strip", "Omit debug info (the release build)");

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .strip = strip,
    });

    const options = b.addOptions();
    options.addOption([]const u8, "version", version);
    exe_mod.addOptions("build_options", options);

    const exe = b.addExecutable(.{
        .name = "ziglint",
        .root_module = exe_mod,
    });

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the application");
    run_step.dependOn(&run_cmd.step);

    const test_step = b.step("test", "Run unit tests");
    const test_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    test_mod.addOptions("build_options", options);
    const exe_tests = b.addTest(.{
        .root_module = test_mod,
    });
    test_step.dependOn(&b.addRunArtifact(exe_tests).step);

    const fmt_check = b.addFmt(.{ .paths = &.{ "src", "build.zig", "build.zig.zon", "site.zig" } });
    test_step.dependOn(&fmt_check.step);

    const lint_step = addLint(b, exe, &.{ b.path("src"), b.path("build.zig"), b.path("site.zig") });
    test_step.dependOn(lint_step);

    // The site's rule and changelog pages, from the files the tool and the
    // release workflow already read. `just doc` runs this first.
    const gen_site = b.addExecutable(.{
        .name = "gen_site",
        .root_module = b.createModule(.{
            .root_source_file = b.path("site.zig"),
            .target = target,
            .optimize = .ReleaseFast,
        }),
    });
    const run_gen_site = b.addRunArtifact(gen_site);
    run_gen_site.addArgs(&.{
        b.pathFromRoot("src/docs/rules"),
        b.pathFromRoot("docs/content"),
    });
    const site_step = b.step("site", "Regenerate the site's rule pages under docs/content");
    site_step.dependOn(&run_gen_site.step);
}

/// Add a ziglint step to your build. Use as a dependency to run linting.
/// The ziglint executable is always built with ReleaseFast for speed.
/// Example usage in a downstream project:
/// ```zig
/// const ziglint_dep = b.dependency("ziglint", .{ .optimize = .ReleaseFast });
/// const lint_step = ziglint.addLint(b, ziglint_dep, &.{ b.path("src"), b.path("build.zig") });
/// b.step("lint", "Run ziglint").dependOn(lint_step);
/// ```
pub fn addLint(
    b: *std.Build,
    ziglint_dep: anytype,
    paths: []const std.Build.LazyPath,
) *std.Build.Step {
    const exe = switch (@TypeOf(ziglint_dep)) {
        *std.Build.Step.Compile => ziglint_dep,
        *std.Build.Dependency => ziglint_dep.artifact("ziglint"),
        *const std.Build.Dependency => ziglint_dep.artifact("ziglint"),
        else => @compileError("expected *Compile or *Dependency"),
    };

    const run = b.addRunArtifact(exe);
    for (paths) |path| {
        run.addDirectoryArg(path);
        addPathInputs(b, run, path);
    }
    run.expectExitCode(0);
    return &run.step;
}

fn addPathInputs(b: *std.Build, run: *std.Build.Step.Run, lazy_path: std.Build.LazyPath) void {
    // Only handle src_path (from b.path()) - other variants may not be resolved yet
    const src = switch (lazy_path) {
        .src_path => |src| src,
        else => return,
    };

    const io = src.owner.graph.io;
    const stat = src.owner.build_root.handle.statFile(io, src.sub_path, .{}) catch return;
    if (stat.kind == .directory) {
        var dir = src.owner.build_root.handle.openDir(io, src.sub_path, .{ .iterate = true }) catch return;
        defer dir.close(io);
        var walker = dir.walk(b.allocator) catch return;
        defer walker.deinit();
        while (walker.next(io) catch null) |entry| {
            if (entry.kind == .file and std.mem.endsWith(u8, entry.basename, ".zig")) {
                run.addFileInput(lazy_path.path(run.step.owner, entry.path));
            }
        }
    } else if (stat.kind == .file) {
        run.addFileInput(lazy_path);
    }
}

fn getVersion(b: *std.Build) []const u8 {
    // A Nix build has no `.git`, so the package passes the version it read
    // from build.zig.zon. Everything else asks git for the described tag.
    if (b.option([]const u8, "version", "The version to report; defaults to `git describe`")) |version| {
        return version;
    }

    var code: u8 = undefined;
    const git_describe = b.runAllowFail(&.{ "git", "describe", "--match", "v*.*.*", "--tags" }, &code, .ignore) catch {
        return "unknown";
    };
    const trimmed = std.mem.trim(u8, git_describe, " \n\r");
    const without_v = if (trimmed.len > 0 and trimmed[0] == 'v') trimmed[1..] else trimmed;

    if (std.mem.findScalar(u8, without_v, '-')) |dash_idx| {
        const tag_part = without_v[0..dash_idx];
        const rest = without_v[dash_idx + 1 ..];
        if (std.mem.findScalar(u8, rest, '-')) |second_dash| {
            const count = rest[0..second_dash];
            const hash = rest[second_dash + 1 ..];
            const hash_without_g = if (hash.len > 0 and hash[0] == 'g') hash[1..] else hash;
            return b.fmt("{s}-{s}+{s}", .{ tag_part, count, hash_without_g });
        }
    }
    return without_v;
}
