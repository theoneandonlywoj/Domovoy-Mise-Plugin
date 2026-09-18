defmodule DomovoyMisePlugin.Runner.InstallTest do
  use ExUnit.Case, async: false

  alias DomovoyCore.Error
  alias DomovoyCore.Node
  alias DomovoyCore.Type.Any, as: AnyType
  alias DomovoyCore.Type.Boolean, as: BooleanType
  alias DomovoyCore.Type.Map, as: MapType
  alias DomovoyCore.Value
  alias DomovoyMisePlugin.Runner.Install
  alias DomovoyMisePlugin.Test.FakeShell
  alias DomovoyMisePlugin.Test.NodeRunner
  alias DomovoyMisePlugin.Type.Executable, as: ExecutableType
  alias DomovoyMisePlugin.Type.ToolTargets

  setup do
    directory =
      Path.join(System.tmp_dir!(), "domovoy-mise-install-#{System.unique_integer([:positive])}")

    File.mkdir_p!(directory)
    on_exit(fn -> File.rm_rf(directory) end)

    {:ok, tmp_dir: directory}
  end

  test "declares typed required inputs and install options" do
    assert Install.__domovoy_core__(:required) == [:worktree, :mise]
    assert Install.Input.__schema__(:type, :worktree) == AnyType
    assert Install.Input.__schema__(:type, :mise) == ExecutableType
    assert Install.Input.__schema__(:type, :targets) == ToolTargets
    assert Install.Input.__schema__(:type, :force) == BooleanType
  end

  test "installs targets and returns a persisted string-key worktree", %{tmp_dir: directory} do
    test_pid = self()

    FakeShell.install(fn command, args, opts ->
      send(test_pid, {:ran, command, args, opts})
      {:ok, "installed\n"}
    end)

    on_exit(&FakeShell.uninstall/0)

    worktree = %{"name" => "dom-16", "path" => directory}

    assert %Value{type: MapType, value: ^worktree} =
             NodeRunner.run(install_node(), input_values(worktree, available_mise()))

    assert_received {:ran, "/usr/local/bin/mise", ["install", "--yes", "--force", "node@24"],
                     opts}

    assert opts == [cd: directory, timeout: 1_800_000]
  end

  test "returns a typed unavailable error", %{tmp_dir: directory} do
    worktree = %{name: "dom-16", path: directory}

    assert %Error{} =
             error =
             NodeRunner.run(
               install_node(),
               input_values(worktree, %{available?: false, executable: nil})
             )

    assert error.type == :mise_unavailable
  end

  @spec install_node() :: Node.t()
  defp install_node do
    Node.new(%{
      name: "install_mise",
      runner: Install,
      type: MapType,
      bind: %{
        worktree: {"worktree", AnyType},
        mise: {"detect_mise", ExecutableType}
      },
      args: %{
        targets: {["node@24"], ToolTargets},
        force: {true, BooleanType}
      }
    })
  end

  @spec input_values(map(), ExecutableType.state()) :: map()
  defp input_values(worktree, mise) do
    %{
      "worktree" => Value.cast!(worktree, MapType),
      "detect_mise" => Value.cast!(mise, ExecutableType)
    }
  end

  @spec available_mise() :: ExecutableType.state()
  defp available_mise, do: %{available?: true, executable: "/usr/local/bin/mise"}
end
