# ziglint for `nix run github:baskingspot/ziglint`. The source is the whole
# tree, because `build.zig test` reads `src/docs/rules/*.md` as well as `src`.
#
# The version is passed in from build.zig.zon, which release-prep.py rewrites:
# a Nix build has no `.git`, so `git describe` cannot answer. If that line ever
# stops matching, this evaluation fails instead of shipping a stale version.
{
  lib,
  stdenv,
  zig_0_16,
}:
let
  version = lib.head (
    builtins.match ''[ ]*\.version = "([^"]+)".*'' (
      lib.findFirst (line: lib.hasInfix ".version = " line) "" (
        lib.splitString "\n" (builtins.readFile ../build.zig.zon)
      )
    )
  );
in
stdenv.mkDerivation {
  pname = "ziglint";
  inherit version;
  src = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.unions [
      ../build.zig
      ../build.zig.zon
      ../src
    ];
  };
  nativeBuildInputs = [ zig_0_16.hook ];
  zigBuildFlags = [ "-Dversion=${version}" ];
  meta = {
    description = "A linter for Zig, to keep an agent on the house style";
    homepage = "https://github.com/baskingspot/ziglint";
    license = lib.licenses.mit;
    mainProgram = "ziglint";
    platforms = lib.platforms.unix;
  };
}
