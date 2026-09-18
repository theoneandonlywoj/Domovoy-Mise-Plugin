# DomovoyMisePlugin

Mise capabilities, types, and runners for Domovoy.

The plugin detects the `mise` executable, trusts supported toolchain
configuration files, installs tools, lists available versions, and searches
the tool catalog in managed worktrees. It builds on `DomovoyCore`; the host
application owns the `DomovoyCore.Runtime`.

Detection represents a missing Mise executable as an unavailable value. Trust
remains an optional no-op, while install, version listing, and search return a
typed `:mise_unavailable` error rather than reporting false success or empty
results.

## Installation

Add the plugin to `mix.exs`:

```elixir
defp deps do
  [
    {:domovoy_mise_plugin, github: "theoneandonlywoj/Domovoy-Mise-Plugin"}
  ]
end
```

## Components

- `DomovoyMisePlugin.Runner.Detect` finds `mise` on `PATH` and returns a
  `DomovoyMisePlugin.Type.Executable` value.
- `DomovoyMisePlugin.Runner.Trust` trusts configuration files in a worktree and
  returns the worktree value unchanged.
- `DomovoyMisePlugin.Runner.Install` installs configured or explicitly targeted
  tools and returns the worktree unchanged.
- `DomovoyMisePlugin.Runner.ListAvailableVersions` returns structured output
  from `mise ls-remote --json`.
- `DomovoyMisePlugin.Runner.SearchTools` searches by partial tool name and
  returns structured name and description rows.
- `DomovoyMisePlugin.Capabilities` exposes the underlying operations without
  requiring a Domovoy graph.

The trust runner checks root configuration files in this order:

1. `mise.toml`
2. `.mise.toml`
3. `.tool-versions`

Only regular files are trusted. Trust commands run sequentially and stop after
the first failure.

## Installing Tools

`Runner.Install` runs `mise install --yes` in the supplied worktree. With an
empty `targets` list, Mise loads its active configuration hierarchy, including
the worktree's `.tool-versions`, `mise.toml`, or `.mise.toml`. The plugin does
not parse those files or restrict Mise to one configuration format.

Explicit targets use Mise syntax and remain opaque to the plugin. Examples:

```text
node@24
github:cli/cli@v2.62.0
cargo:ripgrep[features=pcre2]@latest
```

The install runner supports `force`, `jobs`, `dry_run`, `verbose`,
`include_task_tools`, `include_lazy`, `minimum_release_age`, `monorepo`,
`shared`, `system`, `env`, `quiet`, `locked`, and `silent`. Interactive raw I/O
and `--dry-run-code` are intentionally excluded because Domovoy captures
process output and treats nonzero exits as errors.

## Available Versions

`Runner.ListAvailableVersions` requires either a `target` or `all: true`. It
supports `prefix`, `minimum_release_age`, `no_versions_host`, `prerelease`,
`strict_metadata`, and the applicable shared Mise options. JSON output is
always enabled and decoded directly with `Jason`; no external JSON command is
required.

Each `DomovoyMisePlugin.Type.AvailableVersions` row contains:

```elixir
%{
  version: "24.0.0",
  tool: nil,
  created_at: "2025-05-06T00:00:00Z",
  prerelease: false
}
```

`tool` is populated by Mise in `all` mode. Metadata fields are `nil` when the
backend does not provide them. Backend ordering is preserved.

## Searching Tools

`Runner.SearchTools` defaults to partial-name `contains` matching. `equal` and
`fuzzy` modes are also supported. The runner invokes noninteractive
`mise search --no-header` and returns `DomovoyMisePlugin.Type.SearchResults`:

```elixir
[%{name: "jq", description: "Command-line JSON processor"}]
```

Mise does not currently offer JSON output for `search`, so the plugin parses
the command's two-column output in Elixir. It does not invoke `jq` or another
external parser.

## Compatibility

The option surface follows the current documented Mise CLI. Older Mise
versions that do not recognize a requested option return the corresponding
typed command error. Machine-readable flags such as `--json` and
`--no-header`, the worktree directory, and noninteractive install consent are
controlled by the plugin rather than exposed as runner options.

## Security

`mise trust` permits a repository's Mise configuration to influence tool
installation and command execution. Tool installation can execute backend,
plugin, hook, and post-install code. Only trust and install tools for
repositories and revisions whose configuration is trusted. The plugin passes
the executable and arguments separately through `DomovoyCore.Shell`; it does
not construct a shell command string.

## Development

Install the pinned Erlang and Elixir versions, fetch dependencies, and run:

```sh
mix quality
mix test
```

To activate the repository's Git hooks:

```sh
make hooks-install
```
