+++
title = "ziglint"
+++

Opinionated linting to keep your agent in check.

A compiler does not care that a function is named `MyBadName`, that an import
is unused, or that a materialized type hides a private one. An agent learns
the same way, from the error it gets, and it cannot get one that does not
exist. ziglint is the second reader: 36 rules over the AST, each with a test,
and each with a note that says why the rule exists.

- [Rules](#rules): what the 36 checks cover, and how to turn one off. The [rule reference](rules/) has the note for each.
- [Inline ignores](#inline-ignores): one comment silences one rule on one line, so a deliberate exception costs one line of prose.
- [Reading a rule](#reading-a-rule): `ziglint --explain Z024` prints the note in the terminal, and `--list-rules` prints every code and title.
- [Limits](#limits): no autofix, no formatting, and nothing a parse cannot see.

# Getting started

## Install

ziglint runs `zig` to find the standard library it lints against, so `zig` must
be on `PATH`. `--zig-lib-path` points it at another lib directory.

With Homebrew, on macOS or Linux:

```sh
brew install --cask baskingspot/tap/ziglint
```

With mise:

```sh
mise use -g github:baskingspot/ziglint
```

With Nix:

```sh
nix run github:baskingspot/ziglint
```

Each [release](https://github.com/baskingspot/ziglint/releases) has a tarball
for `linux-x64`, `linux-arm64`, and `macos-arm64`, a zip for `windows-x64`, and
a `SHA256SUMS` file. The archives are attested, so check a download with:

```sh
gh attestation verify FILE -R baskingspot/ziglint --signer-repo baskingspot/gh-actions
```

From source:

```sh
zig build install -Doptimize=ReleaseFast --prefix $HOME/.local
```

## Run it

With no arguments, ziglint reads `.ziglint.zon` in the current directory or the
nearest one above it, and lints the paths that file lists:

```console
$ ziglint
Z024: src/Linter.zig:31: line exceeds 120 bytes (252 bytes)
```

One line per finding on stderr, `CODE: path: line: what it saw`. The exit
status is 1 when a finding exists and 0 when it does not, so a CI job is one
line. Pass paths to override the config:

```sh
ziglint src build.zig
```

## Configure it

`.ziglint.zon` is a plain Zig object:

```zig
.{
    .paths = .{ "src", "build.zig" },
    .rules = .{
        .Z024 = .{ .max_length = 100 },
        .Z033 = .{ .enabled = true },
    },
}
```

A rule with settings takes its own fields; `ziglint --explain RULE` prints the
ones that rule has and the values your file overrides. A rule without a
`config` line in the note takes only `.enabled`.

# Rules

Every rule reads the AST that `std.zig.Ast` gives it, plus a module graph built
from `build.zig` and a type resolver for the rules that need one. The [rule
reference](rules/) has the note for each code, and the examples in a note are
the examples the doc tests run.

A rule that is on by default runs unless the config disables it; Z033 is off by
default. `--only` runs nothing else, and `--ignore` drops one rule:

```sh
ziglint --only Z011 src
ziglint --ignore Z024 --ignore Z033 src
```

# Inline ignores

One comment silences one rule for one line or one declaration:

```zig
fn MyBadName() void {} // ziglint-ignore: Z001
```

```zig
// ziglint-ignore: Z001
fn AnotherBadName() void {}
```

An ignore names one code. Two codes take two comments, and a comment that
names no code silences nothing.

# Reading a rule

```console
$ ziglint --list-rules
Z001  Function names should be camelCase
Z002  Avoid initialized variables that look like named discards
...
$ ziglint --explain Z024
Z024: Line exceeds maximum length
...
```

`--explain` prints the note that the code carries, with the settings your
project overrides first. The note is markdown, so it reads the same in the
terminal and on the [rule reference](rules/).

# Limits

- No autofix. A finding names the line and the rule; the edit is yours.
- No formatting. `zig fmt` owns layout, and ziglint does not run it.
- A rule reads what a parse can see. A name built at comptime, a type that only exists after instantiation, and a generated file are out of reach.
- The rules are opinions. A project that disagrees turns one off in `.ziglint.zon` and says why in the commit that does it.
