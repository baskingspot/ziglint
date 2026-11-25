# Changelog

Changes a user of ziglint notices, newest first, in the
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) form.

## [Unreleased]

## [0.9.0] - 2026-11-24

### Any rule's note, in the terminal

`ziglint --explain Z024` prints what a rule does, what it saw, and how to fix
it, without leaving the terminal. `ziglint --list-rules` prints the index, so a
code in a finding is one command away from its note.

### Added

- `--explain RULE` prints the rule's note, with the settings your `.ziglint.zon`
  overrides first: `max_length: 80 (default: 120)`.
- `--list-rules` prints every code and title, and marks the rules that are off
  by default.

### Changed

- A rule without a note no longer compiles, and the doc tests run every note's
  examples in enum order. A gap cannot ship.

## [0.8.3] - 2026-11-13

### Z011 Finds Deprecations Behind `orelse` and Binary Operators

0.8.2 taught Z011 to resolve a method receiver that is a function parameter,
which is what `b.lazyDependency(...)` in a `build.zig` needs. It did not
cover the shape those calls usually take:

```zig
const testingx_dep = b.lazyDependency("testingx", .{ .target = target }) orelse
    return;
```

The receiver resolved to nothing, so the call went unreported.

### Fixes

- **Parent map (missing edges)**: the map that connects a node to its parent
  covered only a subset of node tags. `orelse` and every binary operator were
  missing, so a walk from a use site to its enclosing function stopped at
  them. The map now covers `orelse`, the arithmetic, bitwise, boolean, and
  shift operators, array access and concatenation, slice expressions, and
  error unions. A call in any of those positions can reach its enclosing
  function again.

  Rules that visit a node to check it now also reach expressions in those
  positions. Against the Zig 0.16 tree this surfaces 27 findings that were
  invisible before (Z004, Z010, Z016, Z017, Z020, Z029) and corrects the type
  name in 3 Z020 messages. Every one was checked: they are calls and
  assertions written inside `orelse` blocks and binary expressions, not
  false positives.

### Verification

- `b.lazyDependency(...) orelse return` is reported; a plain
  `const x = b.lazyDependency(...)` was already reported in 0.8.2.
- New tests cover a deprecated method behind `orelse` and behind a boolean
  operator; both fail without the parent-map fix.
- Whole-tree diff against 0.8.2: `+27` diagnostics, all confirmed above,
  and no rule's output disappears.

## [0.8.2] - 2026-11-13

### Z012 Sees Through Aliases, Z011 Finds Build-File Deprecations

This release fixes a class of Z012 false positives on type aliases, the
false negatives that hid behind them on qualified paths, and the Z011 gap
that kept `b.lazyDependency(...)` in a `build.zig` from being reported.

### Fixes

- **Z012 (aliases are transparent)**: `pub const Code = u40` was reported as
  a private type. The builtin table listed only the common integer widths, so
  `u40` did not count as a primitive and `Code` was never recorded as a type
  declaration. Any alias that reduces to a type the caller can spell is no
  longer reported, whatever its `pub` status: a primitive, another pub type,
  or a shape like `[]const u8` around one. `pub const UINT = c_uint` was the
  same bug, and the C ABI primitives were missing from the table as well.
- **Z012 (local types read as imports)**: a resolver answer of `user_type`
  counted as an import even when the type lived in the same module. That
  excused every local alias to a private type: `const Alias = Hidden;` with a
  private `Hidden` went unreported, as did `const ObjectPointer = *anyopaque`.
- **Z012 (qualified paths)**: `Outer.Inner` in a signature was never checked,
  and an alias whose initializer is a qualified path read as an import. Both
  are checked now: the base must be nameable by the caller and the field must
  be `pub` in its container. Against the Zig 0.16 tree this finds 13 published
  functions that hand out a private nested type, plus one private nested error
  set reported as Z015.
- **Z011 (parameter receivers)**: `fn build(b: *std.Build)` receivers resolved
  to unknown, because the resolver only knew module-level declarations, and
  pointer types resolved with no pointee, so method lookup on `b` or `self`
  found nothing. The resolver now resolves pointer and optional children and
  unwraps them for method lookup, and the linter maps a parameter receiver to
  its declared type. This finds 3 deprecated calls in the Zig 0.16 tree,
  including `std.Build.Cache.addFile` called through `self`.
- **Z011 (multi-line messages)**: a deprecation doc that runs to several lines
  (`std.mem.Allocator.dupeZ`) produced a diagnostic that continued on the next
  output line. The message now carries the deprecation line only.
- **Duplicate diagnostics**: a signature that names the same private type
  twice (`f(a: Hidden, b: Hidden)`) reported the function twice.

### Verification

One diagnostic per report site is now enforced, and the Z012 and Z011 changes
were diffed against the whole Zig 0.16 tree before release: 17 new reports,
all confirmed as genuine findings, and 2 Z012 false positives removed. No
other rule's output changed.

## [0.8.1] - 2026-11-07

### Fixes a Crash Resolving Methods on Nested Stdlib Types

ziglint 0.8.0 could segfault, or report the wrong thing, on a call to a method
of a stdlib type that is declared inside a module std.zig imports, such as
`std.zig.Color.settingFromEnvironment(...)` or
`std.zig.EnvVar.ZIG_LOCAL_CACHE_DIR.get(...)`. Whether it crashed depended on
memory layout, so the same tree could pass on one run and crash on the next,
and passing `--zig-lib-path` only moved the crash around.

### Fixes

- **Resolver (use-after-free)**: the stdlib lookup follows imports through
  paths it owns and frees them when it returns. For a type declared inside an
  imported module, the method's definition kept pointing at that freed path.
  The arena reuses those bytes at once, so Z011, Z029, and the other checks
  that resolve a called function could look the definition up in a different
  module (on Zig 0.17, `std.zig` instead of `zig.zig`) and read past that
  module's node array. The definition now names its module through the module
  graph's own copy of the path.

## [0.8.0] - 2026-10-30

### What's New

#### Z035: Use an alias instead of the qualified path

When a file declares a top-level alias such as `const testing = std.testing;`,
Z035 reports calls that spell the qualified path instead:

```
Z035: test.zig:9: use alias 'testing' instead of 'std.testing'
```

The declaration itself is never reported. This catches the file where one test
uses `testing.expect(...)` and a newly added test uses `std.testing.expect(...)`.
Aliases of namespaces, types, functions, and values are matched by path.
Nested aliases report the longest match once.

A use is skipped when it is an argument to a call, or an operand of `==` or
`!=`, that also names the alias elsewhere in the expression. This keeps tests
such as `expectEqual(alias, path)` from receiving a suggestion that would make
the comparison vacuous.

Known limitations: only top-level aliases initialized directly from a path are
tracked, and path text is compared without resolving shadowed names.

Z035 is enabled by default. Running it over the Zig standard library produces
1,630 findings; running over the baskingspot repositories produced 124 findings
in 34 files.

## [0.7.1] - 2026-10-25

### Fixes Z011 Coverage in Type Positions and Stdlib Aliases

Z011 reported deprecated calls reached by the recursive AST walk, but that walk
stops at function signatures, container fields, and type wrappers. A
`std.meta.Int()` call in a return type or struct field passed without a
warning, while the same call in a function body was reported.

### Fixes

- **Z011 (type positions)**: the rule now sweeps the node table for call
  nodes, so every call is checked exactly once regardless of position. This
  covers function return types, parameter types, struct fields, optional,
  pointer, and array wrappers, return expressions, switch prongs, and
  array/struct initializers.
- **Z011 (stdlib aliases)**: `const copy = std.mem.copyBackwards;
  copy(...)` is reported. Local aliases between functions were already
  followed; aliases whose target lives in the stdlib were not.
- **Z011 (Zig 0.16 `std.meta`)**: `std.meta.Int` (use `@Int`) and
  `std.meta.Tuple` (use `@Tuple`) are the two deprecated constructors in the
  0.16 standard library. Both are now detected in every position.

The wider sweep found 21 calls to the deprecated `std.mem.indexOf`,
`indexOfScalar`, and `indexOfPos` aliases in ziglint itself, hidden under
`orelse` and `or` expressions. They now use `find`, `findScalar`, and
`findPos`.

## [0.7.0] - 2026-10-20

### New Rule and a Z011 Detection Fix

This release adds Z034 and fixes Z011 so that deprecations on whole stdlib
modules are detected, not just deprecations on the called declaration.

### What's New

#### Z034: Use `writeAll` for literal prints on `Io.Writer`

`writer.print("literal", .{})` performs no formatting. With an empty args
tuple, `print` walks the literal and calls `writeAll` on it anyway. The empty
tuple exists only because `print` requires it, and the call reads as if
interpolation was intended. Z034 recommends `writeAll` instead.

The receiver must resolve to `std.Io.Writer`. Unresolved receivers are
skipped because `std.debug.print` and `std.json.Stringify.print` have the
same call shape but no `writeAll` alternative. Function parameters,
explicitly typed locals, top-level declarations, and fields of same-file
types are checked. Alias chains such as `const Io = std.Io;` and
`const Writer = std.Io.Writer;` resolve.

### Fixes

#### Z011: Detect deprecated stdlib modules

A module deprecation is documented on the module declaration, not on each
function it contains. `std.fs.path` is deprecated in Zig 0.16, but its
functions are not, so `std.fs.path.basename(path)` passed without a warning.
Z011 now walks up the receiver's module chain and reports the deprecated
namespace:

```
Z011: main.zig:3: 'std.fs.path' is deprecated: Deprecated, use `std.Io.Dir.path`.
```

The marker parser also accepts the `Deprecated, use ...` comma form used by
128 doc comments in the Zig 0.16 standard library. Previously only
`Deprecated:`, `Deprecated;`, and `Deprecated in favor of` were recognized.

ziglint's own `std.fs.path` calls moved to `std.Io.Dir.path`.

## [0.6.2] - 2026-10-13

### Fixes Z006 False Positives on 0.16 Type-Constructor Builtins

Z006 flagged every PascalCase alias built with a 0.16 type-constructor builtin
(`@Int`, `@Pointer`, `@Struct`, `@Enum`, `@Union`, `@Tuple`, `@Fn`,
`@FieldType`, `@EnumLiteral`). The builtin recognition list predated 0.16:
`@Type` was removed and replaced by these fine-grained constructors, and the
list was never updated for its replacements. Against the 0.16 standard
library, this release removes 24 Z006 false positives (5970 → 5946 reports)
and adds none.

### Fixes

- **Z006 (missing type-constructor builtins)**: the type-returning builtin
  list recognized 7 of 14 builtins. It existed in three stale copies — the
  Linter type-expression check, the resolver builtin-call handling, and the
  resolver builtin type-ref check. All three now read one shared list:
  `TypeResolver.isTypeReturningBuiltin`.
- **Resolver (multi-argument builtin calls)**: only 0-2 argument builtin
  calls reached the resolver builtin handling. Constructors like `@Struct`
  take 4-5 arguments, so they resolved as unknown in module-graph mode.
- **Z006 (`@typeInfo` misclassified)**: the resolver treated `@typeInfo` as
  returning a type. It returns a `std.builtin.Type` value, so PascalCase
  bindings like `const Info = @typeInfo(x);` were silently allowed. They are
  flagged now.

## [0.6.1] - 2026-10-07

### Fixes a 0.6.0 Regression: Member-of-Module Type Aliases Read as Private

0.6.0's resolver work introduced two stacked bugs that made Z012 flag
every `const X = @import("...").X;` file-local alias to a type that is
pub at its definition — up to 115 false positives in a single project
migration. Both are fixed and covered by regression tests.

### Fixes

- **Z012 (bare module imports)**: `isImportedType` treated an unresolved
  resolver answer as an authoritative "not imported" and never reached its
  own syntactic fallback. Build-declared module names (`@import("runtime")`)
  resolve to nothing in the module graph — the syntactic fallback now runs
  for anything the resolver cannot answer.
- **Z012 (member-of-module access)**: `@import("x.zig").Action` answered
  unknown even when `x.zig` was in the module graph — the 0.6.0
  module-root fn search covered method calls (`mod.someFn()`) but not plain
  member access. A module receiver now resolves its member through the
  module's root declarations.

## [0.6.0] - 2026-10-07

### False-Positive Fixes Across the Core Rules

This release clears the false-positive families that forced `ziglint-ignore`
comments across real codebases. Five rule families were misfiring on
idiomatic Zig; each fix was driven by a live corpus of ignores and is
covered by regression tests.

### Highlights

- **Z028**: `const log = @import("log.zig").scoped(.mod);` — chained calls on
  imports are allowed when the result lands in a top-level const. The
  `std.log.scoped` idiom with a project-local module no longer flags.
- **Z015**: composed error sets (`pub const E = A || B || error{...}`) are
  recognized as public type declarations. Every pub function returning one
  was previously flagged as exposing a private error set.
- **Z006**: type aliases built with any type-returning builtin — `@Vector`,
  `@Frame`, `@Struct`, `@Fn`, `@This`, `@TypeOf` — are recognized by a single
  shared list. `const Chunk = @Vector(N, u8)` no longer flags as a camelCase
  variable.
- **Z012**: the private-type check now searches every enclosing container
  (methods of `Connection.Io` referencing types pub in `Connection`), exempts
  container-self references (`fn bar(self: *Foo)`) and `Self = @This()`
  aliases, and understands `union(enum)` containers.
- **Z012 (new coverage)**: pointer, slice, and array signatures are now
  traversed, so `pub fn take(h: *Hidden)` — previously invisible — is
  checked like any other exposure.
- **Z006/Z012 (semantic mode)**: with the module graph, camelCase
  type-functions (std.log-parity `scoped`/`withContext`) resolve through the
  TypeResolver instead of name-shape heuristics. Two resolver bugs fixed on
  the way: `@import("x.zig")` was typed with the importing module's path,
  and module-root functions were unsearchable.
- **Z023 (semantics change)**: the rule now orders structural parameters
  only — `comptime T: type`, then comptime values, then `Allocator`, then
  `Io`. Runtime value parameters are position-free, so writer-first APIs
  (`std.fmt.format(writer, comptime fmt, args)`) and ctx-then-callback
  registrations no longer flag.
- **Crash fix**: container member lookups returned a dangling slice into a
  dead stack frame; only some stack layouts (CI) read garbage and crashed.
  Callers now own the buffer.
- **Z026 docs**: the preferred fix for best-effort stdio catches is now
  documented — a `std.debug.print`-style void wrapper that swallows the
  error once, so call sites never need a catch.

### Breaking Changes

None in the library API. Diagnostic output changes in both directions:
Z023 is relaxed (fewer diagnostics), and Z012 pointer traversal means
genuine exposures through `*T`, `[]T`, and `[N]T` now newly flag.

## [0.5.3] - 2026-07-20

### Safer, More Accurate Lint Fixes

This release focuses on making ziglint diagnostics safe to follow. Suggested
changes now better preserve Zig semantics, avoid false positives, and provide
enough context to produce compiling fixes.

### Highlights

- Z017 now consistently flags `return try expression` and recommends hoisting
  `try` into a local. This preserves payload coercions such as `!Thing` to
  `!?Thing` that can break when `try` is simply removed.
- Z002 now recommends valid discard assignments (`_ = expression;`) or a
  normally named binding instead of misleading underscore declarations.
- Z003 includes the parser's actual error and precise source offset.
- Z004 uses the declaration's real type and tells users to preserve declaration
  kind, modifiers, and initializer fields.
- Z010 only removes explicit struct initializer types when a resolved concrete
  parameter expects that same type. Generic and unresolved calls are left
  unchanged.
- Z016 only rewrites verified `std.debug.assert` calls, avoiding duplicated side
  effects in project-defined `assert` functions.
- Z020 recommends the enclosing type name in named structs and `Self` in
  anonymous structs.
- Z023 consistently places all comptime parameters before `Allocator`, `Io`, and
  ordinary runtime parameters.
- Z028 allows `_ = @import(...)` only in test blocks.
- Z030 uses the actual deinit receiver name and accepts early-return branches
  that explicitly invalidate it.
- Z033 now applies its vague-name policy only to type names, not ordinary
  functions such as `processData`.

Additional corrections clarify deprecation markers, private error-set API
impact, accepted `@This()` aliases, and Z024's byte-based line-length limit.

### Test Coverage

Documentation examples can now include compiler probes. Important suggested
rewrites are checked with `zig test` as well as ziglint, including the nullable
error-union coercion that motivated the Z017 change.

## [0.5.2] - 2026-02-08

### Performance Improvements

#### Module graph construction is now 3000x faster! 🚀

Dramatically improved module graph build performance through two key optimizations:

**Before:** ~1850ms to analyze `build.zig` (loading 308 modules from std with ZIR)
**After:** ~0.6ms to analyze `build.zig` (loading 2 modules without ZIR)

**What changed:**

1. **Disabled ZIR generation** - ZIR was added proactively in v0.4.0 for future control flow analysis (issue #18), but no rules currently use it. Generating ZIR took 10-50ms per module.

2. **Skip recursing into std library** - When linting user code like `build.zig`, we don't need to parse all 300+ modules from the standard library. Now we only load the root `std.zig` file.

**Impact on real-world usage:**

```bash
# Linting a single file that imports std
Before: ~2 seconds
After:  ~0.4 seconds (5x faster)

# Linting entire src/ directory
Before: Previously slow on large projects
After:  Dramatically faster startup and analysis
```

These optimizations can be easily reverted if control flow analysis is implemented in the future (see well-documented code comments in `src/ModuleGraph.zig`).

### Technical Details

- ZIR generation infrastructure remains in place and can be re-enabled by uncommenting documented code sections
- Module graph now loads only user code + top-level std.zig instead of recursively parsing the entire standard library
- All tests pass; linter functionality unchanged
- Verified against GitHub history: ZIR added in commit 14bbe87 but never used by any rules

## [0.5.1] - 2026-02-08

### Bug Fixes

#### Z011: Fixed deprecation detection in nested contexts

Previously, ziglint failed to detect deprecated function calls inside `try` expressions, `catch` blocks, and other nested AST contexts. This was due to incomplete AST traversal in the linter.

**Fixed detection for:**

- `std.meta.intToEnum()` - deprecated in favor of `@enumFromInt()`
- `std.meta.TagPayloadByName()` - deprecated in favor of `TagPayload` with `@field()`
- `std.enums.nameCast()` - deprecated in favor of `@enumFromInt(@intFromEnum())`
- `std.unicode.utf8Decode()` - deprecated in favor of `utf8DecodeAssumeValid()`
- And many other deprecated functions that were previously missed

**Technical details:**

- Fixed `visitChildren()` to recursively visit all child nodes for unhandled AST node types
- Now catches deprecations in try expressions, catch blocks, and other complex contexts
- Added test corpus to prevent regressions

**Example - now detects:**

```zig
pub fn main() !void {
    // Previously missed, now detected:
    _ = try std.meta.intToEnum(MyEnum, 1);
}
```

#### Code Quality

- Fixed Z011 violation in ziglint's own codebase: replaced deprecated `std.mem.trimLeft` with `std.mem.trimStart`
- Fixed Z007 violations: eliminated 20 duplicate `ModuleGraph` imports across test functions
- Added test cases for deprecated functions we don't yet detect (marked as skipped for future work)

### Improvements

- Added `--verbose` flag with timing information for performance analysis
- Added per-rule timing breakdown to verbose output
- Improved verbose output with colors and rule summary
- Better directory linting with verbose logging

### Known Limitations

Detection still requires improvement for:

- Deprecated methods on local variables (requires flow analysis)
- Deprecated const values that aren't function calls

## [0.5.0] - 2026-02-01

### What's New

Three new naming convention rules based on the official Zig Style Guide:

- **Z031**: Avoid underscore prefix in identifiers - detects `_like_this` naming pattern
- **Z032**: Acronyms should use standard casing - detects `XMLParser` (should be `XmlParser`)
- **Z033**: Avoid redundant words in identifiers - detects "Value", "Data", "Context", "Manager", "State", "utils", "misc" (disabled by default)

### Configuration

Z033 is disabled by default as it can be controversial. Enable it in `.ziglint.zon`:

```zig
.{
    .rules = .{
        .Z033 = .{ .enabled = true },
    },
}
```

## [0.4.1] - 2026-01-31

### What's New

#### Bug Fixes

- **Z020**: No longer flags `@This()` when passed as a function argument (e.g., `testing.refAllDecls(@This())`)

## [0.4.0] - 2026-01-31

### What's New

#### New Rules

- **Z028**: Inline `@import` should be assigned to a top-level `const`
- **Z030**: `deinit` functions should set `self.* = undefined`

#### Bug Fixes

- **Z012**: No longer flags pub types within the same enclosing struct as private
- **Z006**: Allows camelCase function aliases (e.g., `const foo = @import("std").debug.print`)
- Fixed directory traversal on Windows

## [0.3.0] - 2026-01-30

### What's New

#### New Lint Rules

- **Z023**: Argument order lint rule - flags comptime value params that should come before runtime params
- **Z024**: Line length lint rule with config file support (`zlint.json`)
- **Z025**: No-catch-return rule - detects `catch return` patterns
- **Z026**: Suppressed-errors rule - flags error suppression patterns
- **Z027**: Flag instance access to container-level decls
- **Z029**: Detect redundant `@as` in result-location contexts

#### Improvements

- Z006: Recognize more type expressions as type aliases including primitive types and PascalCase labeled blocks
- Z011: Improved deprecated stdlib function detection
- TypeResolver: Add type-vs-instance resolution and function call return type resolution
- `--help` and `--version` now exit with code 0

#### Documentation

- Added comprehensive documentation for all linter rules in `docs/rules/`
- Added executable documentation tests for linter rules
- Added nix devShell for development

#### Build

- Added `aarch64-linux` build target to CI and releases

## [0.2.2] - 2026-01-25

### What's New

- Z006: recognize primitive types as valid type aliases
- Fix Z019 false positive for local structs in large functions
- Fix Z019 false positive for structs in if/while/for bodies

## [0.2.1] - 2026-01-24

### What's New

- Build system now caches the lint step properly, skipping re-runs when source files are unchanged
- Diagnostics output to stderr for proper build system integration

## [0.2.0] - 2026-01-24

### What's New

#### New Rules

- **Z017**: Flag redundant `try` in return statements (`return try expr` → `return expr`)
- **Z018**: Flag redundant `@as` when type is already known from context
- **Z019**: `@This()` in named struct; use the type name instead
- **Z020**: Inline `@This()`; assign to a constant first
- **Z021**: File-struct `@This()` alias should match filename
- **Z022**: `@This()` alias in anonymous/local struct should be `Self`

#### Improvements

- Z006: Treat error set merges as type aliases
- TypeResolver: Support aliased std imports
- Fix Z017 message dim color leak
- Fix addLint caching by using LazyPath

#### Removed Rules

- Z008: Comment divider line rule (removed)

## [0.1.0] - 2026-01-22

### What's New

- Initial release of ziglint
- Zig linting and style checks
- Cross-platform support (macOS, Linux, Windows)
