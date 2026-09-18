defmodule DomovoyMisePlugin.Runner.SearchToolsTest do
  use ExUnit.Case, async: false

  alias DomovoyCore.Node
  alias DomovoyCore.Type.Any, as: AnyType
  alias DomovoyCore.Type.String, as: StringType
  alias DomovoyCore.Value
  alias DomovoyMisePlugin.Runner.SearchTools
  alias DomovoyMisePlugin.Test.FakeShell
  alias DomovoyMisePlugin.Test.NodeRunner
  alias DomovoyMisePlugin.Type.Executable, as: ExecutableType
  alias DomovoyMisePlugin.Type.SearchMatch
  alias DomovoyMisePlugin.Type.SearchResults

  setup do
    directory =
      Path.join(System.tmp_dir!(), "domovoy-mise-search-#{System.unique_integer([:positive])}")

    File.mkdir_p!(directory)
    on_exit(fn -> File.rm_rf(directory) end)

    {:ok, tmp_dir: directory}
  end

  test "declares typed search inputs with contains as the default" do
    assert SearchTools.__domovoy_core__(:required) == [:worktree, :mise, :query]
    assert SearchTools.Input.__schema__(:type, :query) == StringType
    assert SearchTools.Input.__schema__(:type, :match_type) == SearchMatch
    assert %SearchTools.Input{match_type: :contains} = struct(SearchTools.Input)
  end

  test "searches tools through the Engine", %{tmp_dir: directory} do
    FakeShell.install(fn _command, _args, _opts ->
      {:ok, "jq  Command-line JSON processor\n"}
    end)

    on_exit(&FakeShell.uninstall/0)

    expected = [%{name: "jq", description: "Command-line JSON processor"}]

    assert %Value{type: SearchResults, value: ^expected} =
             NodeRunner.run(search_node(), input_values(directory))
  end

  @spec search_node() :: Node.t()
  defp search_node do
    Node.new(%{
      name: "search_mise",
      runner: SearchTools,
      type: SearchResults,
      bind: %{
        worktree: {"worktree", AnyType},
        mise: {"detect_mise", ExecutableType}
      },
      args: %{query: {"jq", StringType}}
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
