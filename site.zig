//! Writes the site's generated pages from what the repo already holds.
//!
//! Two trees come out of here, both ignored by git and rebuilt by `just doc`:
//!
//! - `docs/content/rules/`, one page per rule plus an index, from
//!   `src/docs/rules/*.md`. That is the same markdown `ziglint --explain`
//!   prints and the doc tests execute, so the site cannot describe a rule
//!   differently from the tool.
//! - `docs/content/changelog/`, one page per release plus an index, from
//!   `docs/releases/*.md`. That is the same file the release workflow uses as
//!   the release body.
//!
//! Zola reads TOML frontmatter and the rule files carry YAML, so the step
//! exists to add it. Nothing here writes prose: every page is a rewrite of a
//! file a person maintains.

const std = @import("std");

const Rule = struct {
    code: []const u8,
    title: []const u8,
    body: []const u8,
};

const Release = struct {
    version: []const u8,
    summary: []const u8,
    body: []const u8,
};

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;

    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 4) {
        std.debug.print("Usage: {s} <rules-dir> <releases-dir> <content-dir>\n", .{args[0]});
        return error.InvalidArgs;
    }
    const rules_dir = args[1];
    const releases_dir = args[2];
    const content_dir = args[3];

    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const rules = try readRules(arena, io, rules_dir);
    const releases = try readReleases(arena, io, releases_dir);

    try writeRules(arena, io, content_dir, rules);
    try writeChangelog(arena, io, content_dir, releases);
}

fn fail(path: []const u8, err: anyerror) error{InvalidInput} {
    std.debug.print("site: {s}: {s}\n", .{ path, @errorName(err) });
    return error.InvalidInput;
}

fn readFile(allocator: std.mem.Allocator, io: std.Io, path: []const u8) ![]const u8 {
    return std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(8 << 20)) catch |err| {
        return fail(path, err);
    };
}

/// The names of the `.md` files in `dir`, sorted. Only these two directories
/// are ever read, so a flat listing is enough.
fn listMarkdown(allocator: std.mem.Allocator, io: std.Io, dir_path: []const u8) ![]const []const u8 {
    var dir = std.Io.Dir.cwd().openDir(io, dir_path, .{ .iterate = true }) catch |err| {
        return fail(dir_path, err);
    };
    defer dir.close(io);

    var names: std.ArrayList([]const u8) = .empty;
    var walker = dir.walk(allocator) catch |err| {
        return fail(dir_path, err);
    };
    defer walker.deinit();

    while (walker.next(io) catch null) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.basename, ".md")) continue;
        if (entry.path.len != entry.basename.len) continue; // flat only
        try names.append(allocator, try allocator.dupe(u8, entry.basename));
    }
    std.sort.block([]const u8, names.items, {}, byName);
    return names.toOwnedSlice(allocator);
}

fn byName(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.lessThan(u8, a, b);
}

fn byVersionDesc(_: void, a: Release, b: Release) bool {
    return versionOrder(a.version, b.version) == .gt;
}

fn versionOrder(a: []const u8, b: []const u8) std.math.Order {
    const pa = parseVersion(a) orelse return .eq;
    const pb = parseVersion(b) orelse return .eq;
    for (pa, pb) |x, y| {
        if (x != y) return std.math.order(x, y);
    }
    return .eq;
}

fn parseVersion(text: []const u8) ?[3]u64 {
    var version: [3]u64 = .{ 0, 0, 0 };
    var parts = std.mem.splitScalar(u8, std.mem.trimStart(u8, text, "v"), '.');
    var index: usize = 0;
    while (parts.next()) |part| {
        if (index == version.len) return null;
        version[index] = std.fmt.parseInt(u64, part, 10) catch return null;
        index += 1;
    }
    return if (index == 3) version else null;
}

/// Reads the YAML frontmatter the rule files carry and returns the two fields
/// this uses, plus the body with the frontmatter removed.
fn splitFrontmatter(text: []const u8) struct { rule: []const u8, title: []const u8, body: []const u8 } {
    var frontmatter: []const u8 = "";
    var body = text;
    if (std.mem.startsWith(u8, text, "---\n")) {
        const end = std.mem.find(u8, text[4..], "\n---") orelse {
            return .{ .rule = "", .title = "", .body = text };
        };
        frontmatter = text[4..][0..end];
        body = std.mem.trimStart(u8, text[4 + end + 4 ..], "\n");
    }

    var rule: []const u8 = "";
    var title: []const u8 = "";
    var lines = std.mem.splitScalar(u8, frontmatter, '\n');
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, "rule:")) {
            rule = unquote(std.mem.trim(u8, line[5..], " "));
        } else if (std.mem.startsWith(u8, line, "title:")) {
            title = unquote(std.mem.trim(u8, line[6..], " "));
        }
    }
    return .{ .rule = rule, .title = title, .body = body };
}

fn unquote(text: []const u8) []const u8 {
    if (text.len >= 2 and text[0] == '"' and text[text.len - 1] == '"') return text[1 .. text.len - 1];
    return text;
}

fn readRules(allocator: std.mem.Allocator, io: std.Io, dir: []const u8) ![]const Rule {
    const names = try listMarkdown(allocator, io, dir);

    var rules: std.ArrayList(Rule) = .empty;
    for (names) |name| {
        const path = try std.Io.Dir.path.join(allocator, &.{ dir, name });
        const text = try readFile(allocator, io, path);
        const parts = splitFrontmatter(text);
        const code = if (parts.rule.len > 0) parts.rule else std.mem.trimEnd(u8, name, ".md");
        try rules.append(allocator, .{ .code = code, .title = parts.title, .body = parts.body });
    }
    std.sort.block(Rule, rules.items, {}, byCode);
    return rules.toOwnedSlice(allocator);
}

fn byCode(_: void, a: Rule, b: Rule) bool {
    return std.mem.lessThan(u8, a.code, b.code);
}

fn readReleases(allocator: std.mem.Allocator, io: std.Io, dir: []const u8) ![]const Release {
    const names = try listMarkdown(allocator, io, dir);

    var releases: std.ArrayList(Release) = .empty;
    for (names) |name| {
        const version = std.mem.trimEnd(u8, name, ".md");
        if (parseVersion(version) == null) continue;
        const path = try std.Io.Dir.path.join(allocator, &.{ dir, name });
        const text = try readFile(allocator, io, path);
        try releases.append(allocator, .{
            .version = version,
            .summary = summaryLine(text),
            .body = std.mem.trim(u8, text, "\n"),
        });
    }
    std.sort.block(Release, releases.items, {}, byVersionDesc);
    return releases.toOwnedSlice(allocator);
}

/// The note's first `## ` heading, which is its title in one line.
fn summaryLine(text: []const u8) []const u8 {
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, "## ")) return std.mem.trim(u8, line[3..], " ");
    }
    return "";
}

fn writePage(allocator: std.mem.Allocator, io: std.Io, dir: []const u8, name: []const u8, title: []const u8, template: []const u8, body: []const u8) !void {
    const escaped = try escapeToml(allocator, title);
    const page = try std.fmt.allocPrint(
        allocator,
        "+++\ntitle = \"{s}\"\ntemplate = \"{s}\"\n+++\n\n{s}\n",
        .{ escaped, template, std.mem.trim(u8, body, "\n") },
    );
    const path = try std.Io.Dir.path.join(allocator, &.{ dir, name });
    std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = page }) catch |err| {
        return fail(path, err);
    };
}

fn escapeToml(allocator: std.mem.Allocator, text: []const u8) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    for (text) |byte| {
        switch (byte) {
            '"', '\\' => {
                try out.append(allocator, '\\');
                try out.append(allocator, byte);
            },
            else => try out.append(allocator, byte),
        }
    }
    return out.toOwnedSlice(allocator);
}

fn replaceDir(io: std.Io, path: []const u8) !void {
    // deleteTree returns without error when the path is already gone.
    std.Io.Dir.cwd().deleteTree(io, path) catch |err| return fail(path, err);
    std.Io.Dir.cwd().createDirPath(io, path) catch |err| {
        return fail(path, err);
    };
}

fn writeRules(allocator: std.mem.Allocator, io: std.Io, content_dir: []const u8, rules: []const Rule) !void {
    const dir = try std.Io.Dir.path.join(allocator, &.{ content_dir, "rules" });
    try replaceDir(io, dir);

    var index: std.ArrayList(u8) = .empty;
    try index.appendSlice(allocator, "# Rules\n\n");
    try index.appendSlice(allocator, "`ziglint --explain RULE` prints one of these in the terminal. The examples are the ones the doc tests run, so a rule that stops behaving as written fails CI.\n\n");
    for (rules) |rule| {
        const slug = try lowercase(allocator, rule.code);
        try writePage(
            allocator,
            io,
            dir,
            try std.fmt.allocPrint(allocator, "{s}.md", .{slug}),
            try std.fmt.allocPrint(allocator, "{s}: {s}", .{ rule.code, rule.title }),
            "page.html",
            try protectTera(allocator, try ruleLinks(allocator, rule.body)),
        );
        try index.appendSlice(allocator, try std.fmt.allocPrint(allocator, "- [{s}: {s}]({s}/)\n", .{ rule.code, rule.title, slug }));
    }
    try writePage(allocator, io, dir, "_index.md", "Rules", "index.html", index.items);
}

fn writeChangelog(allocator: std.mem.Allocator, io: std.Io, content_dir: []const u8, releases: []const Release) !void {
    const dir = try std.Io.Dir.path.join(allocator, &.{ content_dir, "changelog" });
    try replaceDir(io, dir);

    var index: std.ArrayList(u8) = .empty;
    try index.appendSlice(allocator, "# Changelog\n\n");
    try index.appendSlice(allocator, "What changed in each release, newest first. A note is written once: the release workflow uses the same file as the GitHub release body.\n\n");
    for (releases) |release| {
        const summary = if (release.summary.len > 0)
            try std.fmt.allocPrint(allocator, "{s}: {s}", .{ release.version, release.summary })
        else
            release.version;
        try writePage(
            allocator,
            io,
            dir,
            try std.fmt.allocPrint(allocator, "{s}.md", .{release.version}),
            release.version,
            "page.html",
            try std.fmt.allocPrint(allocator, "# {s}\n\n{s}", .{ release.version, release.body }),
        );
        try index.appendSlice(allocator, try std.fmt.allocPrint(allocator, "- [{s}]({s}/)\n", .{ summary, release.version }));
    }
    try writePage(allocator, io, dir, "_index.md", "Changelog", "index.html", index.items);
}

/// A rule that mentions another writes `[Z005](Z005.md)`, which is right for a
/// file beside it and wrong for a page whose path is `z005/`. Rewrite those
/// links; an outside link is left alone.
fn ruleLinks(allocator: std.mem.Allocator, body: []const u8) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    var rest = body;
    while (std.mem.find(u8, rest, "](Z")) |start| {
        const after = start + 3;
        if (rest.len < after + 6) break;
        const code = rest[after .. after + 3];
        const tail = rest[after + 3 ..];
        if (!std.mem.startsWith(u8, tail, ".md)") or !std.ascii.isDigit(code[0]) or !std.ascii.isDigit(code[1]) or !std.ascii.isDigit(code[2])) {
            try out.appendSlice(allocator, rest[0..after]);
            rest = rest[after..];
            continue;
        }
        try out.appendSlice(allocator, rest[0 .. start + 2]);
        try out.appendSlice(allocator, "../z");
        for (code) |byte| try out.append(allocator, std.ascii.toLower(byte));
        try out.appendSlice(allocator, "/)");
        rest = rest[after + 7 ..];
    }
    try out.appendSlice(allocator, rest);
    return out.toOwnedSlice(allocator);
}

/// Zola renders every page through Tera before markdown, so a code sample that
/// contains `{{` is an expression to it. Z034 has `writer.print("{{}}", .{})`.
/// Wrap such a body in Tera's raw block. The markdown twin keeps the two tags;
/// the alternative is a corrupt example.
fn protectTera(allocator: std.mem.Allocator, body: []const u8) ![]const u8 {
    if (std.mem.find(u8, body, "{{") == null and std.mem.find(u8, body, "{%") == null) return body;
    return std.fmt.allocPrint(allocator, "{{% raw %}}\n{s}\n{{% endraw %}}", .{body});
}

fn lowercase(allocator: std.mem.Allocator, text: []const u8) ![]const u8 {
    const out = try allocator.dupe(u8, text);
    for (out) |*byte| byte.* = std.ascii.toLower(byte.*);
    return out;
}
