defmodule DomovoyMisePlugin.Runner.ListAvailableVersionsTest do
  use ExUnit.Case, async: false

  alias DomovoyCore.Node
  alias DomovoyCore.Type.Any, as: AnyType
  alias DomovoyCore.Value
  alias DomovoyMisePlugin.Runner.ListAvailableVersions
  alias DomovoyMisePlugin.Test.FakeShell
  alias DomovoyMisePlugin.Test.NodeRunner
  alias DomovoyMisePlugin.Type.AvailableVersions
  alias DomovoyMisePlugin.Type.Executable, as: ExecutableType
  alias DomovoyMisePlugin.Type.ToolTarget

  setup do
    directory =
      Path.join(System.tmp_dir!(), "domovoy-mise-versions-#{System.unique_integer([:positive])}")

    File.mkdir_p!(directory)
    on_exit(fn -> File.rm_rf(directory) end)

    {:ok, tmp_dir: directory}
  end

  test "declares typed worktree, Mise, and target inputs" do
    assert ListAvailableVersions.__domovoy_core__(:required) == [:worktree, :mise]
    assert ListAvailableVersions.Input.__schema__(:type, :worktree) == AnyType
    assert ListAvailableVersions.Input.__schema__(:type, :mise) == ExecutableType
    assert ListAvailableVersions.Input.__schema__(:type, :target) == ToolTarget
  end

  test "lists available versions through the Engine", %{tmp_dir: directory} do
    FakeShell.install(fn _command, _args, _opts ->
      {:ok, ~s([{"version":"24.0.0","prerelease":false}])}
    end)

    on_exit(&FakeShell.uninstall/0)

    expected = [
      %{version: "24.0.0", tool: nil, created_at: nil, prerelease: false}
    ]

    assert %Value{type: AvailableVersions, value: ^expected} =
             NodeRunner.run(version_node(), input_values(directory))
  end

  @spec version_node() :: Node.t()
  defp version_node do
    Node.new(%{
      name: "list_node_versions",
      runner: ListAvailableVersions,
      type: AvailableVersions,
      bind: %{
        worktree: {"worktree", AnyType},
        mise: {"detect_mise", ExecutableType}
      },
      args: %{target: {"node@24", ToolTarget}}
    })
  end

  @spec input_values(String.t()) :: map()
  defp input_values(directory) do
    %{
      "worktree" => Value.cast!(%{path: directory}, AnyType),
      "detect_mise" =>
        Value.cast!(
          %{available?: true, executable: "/usr/local/bin/mise"},
          ExecutableType
        )
    }
  end
end
