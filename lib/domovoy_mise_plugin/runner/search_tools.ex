defmodule DomovoyMisePlugin.Runner.SearchTools do
  @moduledoc """
  Searches Mise's tool catalog and returns structured rows.

  Partial-name matching defaults to `:contains`. `:equal` and `:fuzzy` are also
  available. The output is intended for a node with
  `DomovoyMisePlugin.Type.SearchResults`.
  """

  use DomovoyCore.Runner

  alias DomovoyCore.Context
  alias DomovoyCore.Runner
  alias DomovoyCore.Type.Any
  alias DomovoyCore.Type.Boolean
  alias DomovoyCore.Type.Integer
  alias DomovoyCore.Type.String, as: StringType
  alias DomovoyMisePlugin.Capabilities
  alias DomovoyMisePlugin.Type.Executable
  alias DomovoyMisePlugin.Type.SearchMatch

  @option_fields [:env, :jobs, :quiet, :verbose, :locked, :silent]

  input do
    field(:worktree, Any)
    field(:mise, Executable)
    field(:query, StringType)
    field(:match_type, SearchMatch, default: :contains)
    field(:env, StringType)
    field(:jobs, Integer)
    field(:quiet, Boolean, default: false)
    field(:verbose, Integer, default: 0)
    field(:locked, Boolean, default: false)
    field(:silent, Boolean, default: false)
  end

  required([:worktree, :mise, :query])

  @impl Runner
  @spec run(input :: Input.t(), context :: Context.t()) :: Runner.result()
  def run(
        %Input{worktree: worktree, mise: mise, query: query, match_type: match_type} = input,
        %Context{node: node_name}
      ) do
    with {:ok, worktree_path} <- worktree_path(worktree, node_name) do
      Capabilities.search_tools(
        worktree_path,
        mise,
        query,
        match_type,
        options(input),
        node_name
      )
    end
  end

  @spec options(Input.t()) :: map()
  defp options(input), do: input |> Map.from_struct() |> Map.take(@option_fields)

  @spec worktree_path(any(), String.t() | nil) ::
          {:ok, String.t()} | {:error, DomovoyCore.Error.t()}
  defp worktree_path(worktree, node_name) do
    case Capabilities.worktree_path(worktree) do
      {:ok, path} -> {:ok, path}
      :error -> {:error, Capabilities.invalid_worktree_error(node_name)}
    end
  end
end
