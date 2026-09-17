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
end
