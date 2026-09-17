# DomovoyMisePlugin

Mise capabilities, types, and runners for Domovoy.

The plugin detects the `mise` executable and trusts supported toolchain
configuration files in managed worktrees. It builds on `DomovoyCore`; the host
application owns the `DomovoyCore.Runtime`.

Mise is optional. A workflow receives an unavailable executable state and
continues when `mise` is not installed.

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
- `DomovoyMisePlugin.Capabilities` exposes the underlying detection and trust
  operations.

The trust runner checks root configuration files in this order:

1. `mise.toml`
2. `.mise.toml`
3. `.tool-versions`

Only regular files are trusted. Trust commands run sequentially and stop after
the first failure.

## Security

`mise trust` permits a repository's Mise configuration to influence tool
installation and command execution. Only run the trust runner for repositories
and revisions whose configuration is trusted. The plugin passes the executable
and arguments separately through `DomovoyCore.Shell`; it does not construct a
shell command string.

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
