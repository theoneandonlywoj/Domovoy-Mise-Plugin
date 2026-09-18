defmodule DomovoyMisePlugin.CapabilitiesTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias DomovoyCore.Error
  alias DomovoyMisePlugin.Capabilities
  alias DomovoyMisePlugin.Test.FakeShell

  doctest Capabilities, only: [trust_failed_error: 3]

  @node_name "trust_mise"

  setup do
    directory =
      Path.join(
        System.tmp_dir!(),
        "domovoy-mise-capabilities-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(directory)
    on_exit(fn -> File.rm_rf(directory) end)

    {:ok, tmp_dir: directory}
  end

  test "detects the installed Mise state" do
    assert {:ok, state} = Capabilities.detect_executable()

    expected =
      case System.find_executable("mise") do
        nil -> %{available?: false, executable: nil}
        executable -> %{available?: true, executable: executable}
      end

    assert state == expected
  end

  test "reads atom and persisted string worktree paths", %{tmp_dir: directory} do
    assert Capabilities.worktree_path(%{path: directory}) == {:ok, directory}
    assert Capabilities.worktree_path(%{"path" => directory}) == {:ok, directory}
    assert Capabilities.worktree_path(%{path: nil}) == :error
  end

  test "returns supported regular configuration files in order", %{tmp_dir: directory} do
    mise_toml = Path.join(directory, "mise.toml")
    dot_mise_toml = Path.join(directory, ".mise.toml")
    tool_versions = Path.join(directory, ".tool-versions")

    File.write!(tool_versions, "elixir 1.20\n")
    File.mkdir!(dot_mise_toml)
    File.write!(mise_toml, "[tools]\n")

    assert Capabilities.config_paths(directory) == [mise_toml, tool_versions]
  end

  test "skips trust when Mise is unavailable", %{tmp_dir: directory} do
    FakeShell.install(fn _command, _args, _opts -> flunk("the shell must not run") end)
    on_exit(&FakeShell.uninstall/0)

    log =
      capture_log(fn ->
        assert :ok =
                 Capabilities.trust_worktree_configs(
                   directory,
                   %{available?: false, executable: nil},
                   @node_name
                 )
      end)

    assert log =~ "Mise is not installed"
  end

  test "trusts each configuration file in supported order", %{tmp_dir: directory} do
    mise_toml = Path.join(directory, "mise.toml")
    tool_versions = Path.join(directory, ".tool-versions")
    File.write!(mise_toml, "[tools]\n")
    File.write!(tool_versions, "elixir 1.20\n")

    test_pid = self()

    FakeShell.install(fn command, args, opts ->
      send(test_pid, {:ran, command, args, opts})
      {:ok, "trusted\n"}
    end)

    on_exit(&FakeShell.uninstall/0)

    assert :ok =
             Capabilities.trust_worktree_configs(
               directory,
               %{available?: true, executable: "/usr/local/bin/mise"},
               @node_name
             )

    assert_received {:ran, "/usr/local/bin/mise", ["trust", ^mise_toml], first_opts}
    assert_received {:ran, "/usr/local/bin/mise", ["trust", ^tool_versions], second_opts}
    assert first_opts == [cd: directory, timeout: 30_000]
    assert second_opts == [cd: directory, timeout: 30_000]
  end

  test "stops at the first failed trust command", %{tmp_dir: directory} do
    mise_toml = Path.join(directory, "mise.toml")
    tool_versions = Path.join(directory, ".tool-versions")
    File.write!(mise_toml, "[tools]\n")
    File.write!(tool_versions, "elixir 1.20\n")

    test_pid = self()

    FakeShell.install(fn _command, ["trust", config_path], _opts ->
      send(test_pid, {:ran, config_path})
      {:error, "command exited with status 1"}
    end)

    on_exit(&FakeShell.uninstall/0)

    assert {:error, %Error{} = error} =
             Capabilities.trust_worktree_configs(
               directory,
               %{available?: true, executable: "/usr/local/bin/mise"},
               @node_name
             )

    assert error.type == :mise_trust_failed
    assert error.reason == "command exited with status 1"

    assert error.metadata == %{
             command: ["mise", "trust", mise_toml],
             node_name: @node_name,
             field_name: :mise
           }

    assert_received {:ran, ^mise_toml}
    refute_received {:ran, ^tool_versions}
  end

  test "runs bare install in the worktree for active configuration", %{tmp_dir: directory} do
    File.write!(Path.join(directory, ".tool-versions"), "elixir 1.20\n")
    test_pid = self()

    FakeShell.install(fn command, args, opts ->
      send(test_pid, {:ran, command, args, opts})
      {:ok, "installed\n"}
    end)

    on_exit(&FakeShell.uninstall/0)

    assert :ok =
             Capabilities.install_worktree_tools(
               directory,
               available_mise(),
               [],
               %{},
               "install_mise"
             )

    assert_received {:ran, "/usr/local/bin/mise", ["install", "--yes"], opts}
    assert opts == [cd: directory, timeout: 1_800_000]
  end

  test "passes install targets and noninteractive options", %{tmp_dir: directory} do
    test_pid = self()

    FakeShell.install(fn command, args, opts ->
      send(test_pid, {:ran, command, args, opts})
      {:ok, "installed\n"}
    end)

    on_exit(&FakeShell.uninstall/0)

    options = %{
      force: true,
      jobs: 2,
      dry_run: true,
      verbose: 2,
      include_task_tools: true,
      include_lazy: true,
      minimum_release_age: "30d",
      monorepo: true,
      shared: "/opt/mise",
      env: "ci",
      quiet: true,
      locked: true,
      silent: true
    }

    targets = ["node@24", "github:BurntSushi/ripgrep@latest"]

    assert :ok =
             Capabilities.install_worktree_tools(
               directory,
               available_mise(),
               targets,
               options,
               "install_mise"
             )

    assert_received {:ran, "/usr/local/bin/mise", args, opts}

    assert args == [
             "install",
             "--yes",
             "--force",
             "--dry-run",
             "--include-task-tools",
             "--include-lazy",
             "--minimum-release-age",
             "30d",
             "--monorepo",
             "--shared",
             "/opt/mise",
             "--env",
             "ci",
             "--jobs",
             "2",
             "--quiet",
             "--verbose",
             "--verbose",
             "--locked",
             "--silent",
             "node@24",
             "github:BurntSushi/ripgrep@latest"
           ]

    assert opts == [cd: directory, timeout: 1_800_000]
  end

  test "returns an error instead of skipping install when Mise is unavailable", %{
    tmp_dir: directory
  } do
    FakeShell.install(fn _command, _args, _opts -> flunk("the shell must not run") end)
    on_exit(&FakeShell.uninstall/0)

    assert {:error, %Error{} = error} =
             Capabilities.install_worktree_tools(
               directory,
               %{available?: false, executable: nil},
               [],
               %{},
               "install_mise"
             )

    assert error.type == :mise_unavailable
    assert error.metadata.operation == :install
  end

  test "rejects conflicting install options before running Mise", %{tmp_dir: directory} do
    FakeShell.install(fn _command, _args, _opts -> flunk("the shell must not run") end)
    on_exit(&FakeShell.uninstall/0)

    assert {:error, %Error{} = error} =
             Capabilities.install_worktree_tools(
               directory,
               available_mise(),
               [],
               %{shared: "/opt/mise", system: true},
               "install_mise"
             )

    assert error.type == :mise_invalid_options
    assert error.reason.cause == :shared_conflicts_with_system
  end

  test "lists and normalizes available versions", %{tmp_dir: directory} do
    test_pid = self()

    FakeShell.install(fn command, args, opts ->
      send(test_pid, {:ran, command, args, opts})

      {:ok,
       ~s([{"version":"24.0.0","created_at":"2025-05-06T00:00:00Z"},{"version":"24.1.0","prerelease":false}])}
    end)

    on_exit(&FakeShell.uninstall/0)

    assert {:ok, versions} =
             Capabilities.list_available_versions(
               directory,
               available_mise(),
               "node@24",
               %{
                 minimum_release_age: "30d",
                 no_versions_host: true,
                 prerelease: true,
                 strict_metadata: true,
                 jobs: 3,
                 verbose: 1
               },
               "list_node_versions"
             )

    assert versions == [
             %{
               version: "24.0.0",
               tool: nil,
               created_at: "2025-05-06T00:00:00Z",
               prerelease: nil
             },
             %{version: "24.1.0", tool: nil, created_at: nil, prerelease: false}
           ]

    assert_received {:ran, "/usr/local/bin/mise", args, opts}

    assert args == [
             "ls-remote",
             "--json",
             "--minimum-release-age",
             "30d",
             "--no-versions-host",
             "--prerelease",
             "--strict-metadata",
             "--jobs",
             "3",
             "--verbose",
             "node@24"
           ]

    assert opts == [cd: directory, timeout: 120_000]
  end

  test "lists all tools and preserves tool names", %{tmp_dir: directory} do
    FakeShell.install(fn _command, _args, _opts ->
      {:ok, ~s([{"tool":"node","version":"24.0.0","prerelease":null}])}
    end)

    on_exit(&FakeShell.uninstall/0)

    assert {:ok,
            [
              %{tool: "node", version: "24.0.0", created_at: nil, prerelease: nil}
            ]} =
             Capabilities.list_available_versions(
               directory,
               available_mise(),
               nil,
               %{all: true},
               "list_all_versions"
             )
  end

  test "returns a typed error for invalid version JSON", %{tmp_dir: directory} do
    FakeShell.install(fn _command, _args, _opts -> {:ok, "mise warning\n[]"} end)
    on_exit(&FakeShell.uninstall/0)

    assert {:error, %Error{} = error} =
             Capabilities.list_available_versions(
               directory,
               available_mise(),
               "node",
               %{},
               "list_node_versions"
             )

    assert error.type == :mise_invalid_output
    assert error.reason == %{operation: :list_versions}
  end

  test "searches by partial name and parses descriptions", %{tmp_dir: directory} do
    test_pid = self()

    FakeShell.install(fn command, args, opts ->
      send(test_pid, {:ran, command, args, opts})

      {:ok,
       "gojq  Pure Go implementation of jq. https://github.com/itchyny/gojq\n" <>
         "jq    Command-line JSON processor. https://github.com/jqlang/jq\n"}
    end)

    on_exit(&FakeShell.uninstall/0)

    assert {:ok, results} =
             Capabilities.search_tools(
               directory,
               available_mise(),
               "jq",
               :contains,
               %{env: "ci", quiet: true},
               "search_mise"
             )

    assert results == [
             %{
               name: "gojq",
               description: "Pure Go implementation of jq. https://github.com/itchyny/gojq"
             },
             %{
               name: "jq",
               description: "Command-line JSON processor. https://github.com/jqlang/jq"
             }
           ]

    assert_received {:ran, "/usr/local/bin/mise", args, opts}

    assert args == [
             "search",
             "--match-type",
             "contains",
             "--no-header",
             "--env",
             "ci",
             "--quiet",
             "jq"
           ]

    assert opts == [cd: directory, timeout: 30_000]
  end

  test "returns operation-specific command failures", %{tmp_dir: directory} do
    FakeShell.install(fn _command, _args, _opts -> {:error, "network unavailable"} end)
    on_exit(&FakeShell.uninstall/0)

    assert {:error, %Error{} = error} =
             Capabilities.search_tools(
               directory,
               available_mise(),
               "jq",
               :contains,
               %{},
               "search_mise"
             )

    assert error.type == :mise_search_failed
    assert error.reason == "network unavailable"
    assert error.metadata.command == ["mise", "search"]
  end

  @spec available_mise() :: Capabilities.executable_state()
  defp available_mise do
    %{available?: true, executable: "/usr/local/bin/mise"}
  end
end
