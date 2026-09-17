defmodule DomovoyMisePlugin.Runner.TrustTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias DomovoyCore.Error
  alias DomovoyCore.Node
  alias DomovoyCore.Type.Any, as: AnyType
  alias DomovoyCore.Type.Map, as: MapType
  alias DomovoyCore.Value
  alias DomovoyMisePlugin.Runner.Trust
  alias DomovoyMisePlugin.Test.FakeShell
  alias DomovoyMisePlugin.Test.NodeRunner
  alias DomovoyMisePlugin.Type.Executable, as: ExecutableType

  setup do
    directory =
      Path.join(
        System.tmp_dir!(),
        "domovoy-mise-trust-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(directory)
    on_exit(fn -> File.rm_rf(directory) end)

    {:ok, tmp_dir: directory}
  end

  test "declares typed worktree and Mise inputs" do
    assert Trust.__domovoy_core__(:required) == [:worktree, :mise]
    assert Trust.Input.__schema__(:type, :worktree) == AnyType
    assert Trust.Input.__schema__(:type, :mise) == ExecutableType
  end

  test "returns a foreign worktree unchanged when Mise is unavailable", %{tmp_dir: directory} do
    worktree = %{name: "dom-14", path: directory, branch: "dom-14-mise-inputs"}

    capture_log(fn ->
      send(
        self(),
        {:value, NodeRunner.run(trust_node(), input_values(worktree, unavailable_mise()))}
      )
    end)

    assert_received {:value, value}
    assert %Value{type: MapType, value: ^worktree} = value
  end

  test "trusts worktree configuration and returns the foreign value", %{tmp_dir: directory} do
    config_path = Path.join(directory, "mise.toml")
    File.write!(config_path, "[tools]\n")
    test_pid = self()

    FakeShell.install(fn command, args, opts ->
      send(test_pid, {:ran, command, args, opts})
      {:ok, "trusted\n"}
    end)

    on_exit(&FakeShell.uninstall/0)

    worktree = %{name: "dom-14", path: directory, branch: "dom-14-mise-inputs"}
    mise = %{available?: true, executable: "/usr/local/bin/mise"}

    assert %Value{type: MapType, value: ^worktree} =
             NodeRunner.run(trust_node(), input_values(worktree, mise))

    assert_received {:ran, "/usr/local/bin/mise", ["trust", ^config_path], opts}
    assert opts == [cd: directory, timeout: 30_000]
  end

  test "returns a typed error when Mise trust fails", %{tmp_dir: directory} do
    config_path = Path.join(directory, "mise.toml")
    File.write!(config_path, "[tools]\n")

    FakeShell.install(fn _command, _args, _opts -> {:error, "permission denied"} end)
    on_exit(&FakeShell.uninstall/0)

    worktree = %{name: "dom-14", path: directory}
    mise = %{available?: true, executable: "/usr/local/bin/mise"}

    assert %Error{} = error = NodeRunner.run(trust_node(), input_values(worktree, mise))
    assert error.type == :mise_trust_failed
    assert error.reason == "permission denied"

    assert error.metadata == %{
             command: ["mise", "trust", config_path],
             node_name: "trust_mise",
             field_name: :mise
           }
  end

  @spec trust_node() :: Node.t()
  defp trust_node do
    Node.new(%{
      name: "trust_mise",
      runner: Trust,
      type: MapType,
      bind: %{
        worktree: {"worktree", AnyType},
        mise: {"detect_mise", ExecutableType}
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

  @spec unavailable_mise() :: ExecutableType.state()
  defp unavailable_mise, do: %{available?: false, executable: nil}
end
