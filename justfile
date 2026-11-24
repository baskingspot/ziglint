# ziglint: opinionated linting, in 35 rules. `just --list` shows the recipes.
# AGENTS.md holds the working conventions.

[private]
default:
    @just --list

[doc("Unit tests. `zig build test` also runs zig fmt and ziglint on this source")]
[group("test")]
test:
    zig build test --summary all

[doc("Build the Nix package in the sandbox with no network, and print its version. A Nix build has no .git, so the version comes from build.zig.zon")]
[group("test")]
package:
    nix build .#ziglint --print-build-logs
    ./result/bin/ziglint --version

[doc("Compile every target the release ships: aarch64-macos, aarch64-linux, x86_64-linux, x86_64-windows")]
[group("test")]
build-targets:
    #!/usr/bin/env bash
    set -euo pipefail
    for target in aarch64-macos aarch64-linux x86_64-linux x86_64-windows; do
        echo "building ${target}"
        zig build -Doptimize=ReleaseFast -Dtarget="${target}"
    done

[doc("Lint Nix, Markdown, the workflows, and this justfile: nix fmt, oxfmt, actionlint, zizmor, and just --fmt. Zig is ziglint's own business: `zig build test` runs it on src. docs/releases is history and stays as written")]
[group("lint")]
lint:
    nix fmt -- --ci
    oxfmt --check README.md AGENTS.md .github
    actionlint
    zizmor .
    just --fmt --check

[doc("Format everything lint checks")]
[group("lint")]
fmt:
    nix fmt
    oxfmt README.md AGENTS.md .github
    just --fmt

[doc("Regenerate docs/content/rules and docs/content/changelog from src/docs/rules and docs/releases")]
[group("docs")]
reference:
    zig build site

[doc("Build the site into zig-out/site/ziglint/: the guide, the rule reference, and the changelog. The router in baskingspot/site serves /ziglint/... from it")]
[group("docs")]
doc: reference
    baskingspot-docs build ziglint

[doc("Edit the guide with live reload (http://127.0.0.1:1111)")]
[group("docs")]
guide: reference
    baskingspot-docs serve ziglint

[doc("Deploy the rendered site to Cloudflare as an assets-only Worker (config in wrangler.jsonc). Needs CLOUDFLARE_API_TOKEN in the environment, plus CLOUDFLARE_ACCOUNT_ID if the token can see more than one account")]
[group("docs")]
doc-deploy: doc
    wrangler deploy

[doc("Build one release target into the prefix DIR, so the program lands in DIR/bin. The shared release workflow bundles it: the archive name and layout are the org's, not this repo's")]
[group("release")]
release-build TARGET DIR:
    zig build -Doptimize=ReleaseFast -Dtarget={{ TARGET }} --prefix {{ DIR }}

[doc("Tag a release and push the tag, which starts the release workflow. Checks first: a clean tree on main, level with origin")]
[group("release")]
release VERSION:
    #!/usr/bin/env bash
    set -euo pipefail
    test -z "$(git status --porcelain)" || { echo "the tree is not clean" >&2; exit 1; }
    test "$(git branch --show-current)" = main || { echo "not on main" >&2; exit 1; }
    git fetch --quiet origin main
    test "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" || { echo "main is not level with origin" >&2; exit 1; }
    git tag -s "v{{ VERSION }}" -m "v{{ VERSION }}"
    git push origin "v{{ VERSION }}"

[doc("Everything CI runs: the tests, the Nix package, the cross-target compile, the lint, and the docs build")]
[group("ci")]
ci: test package build-targets lint doc
