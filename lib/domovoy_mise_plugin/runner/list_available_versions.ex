defmodule DomovoyMisePlugin.Runner.ListAvailableVersions do
  @moduledoc """
  Lists versions available to install through Mise.

  Supply one `target`, optionally with a version prefix, or set `all` to list
  every tool known to Mise. The output is intended for a node with
  `DomovoyMisePlugin.Type.AvailableVersions`.
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
  alias DomovoyMisePlugin.Type.ToolTarget

  @option_fields [
    :prefix,
    :all,
    :minimum_release_age,
    :no_versions_host,
    :prerelease,
    :strict_metadata,
    :env,
    :jobs,
    :quiet,
    :verbose,
    :locked,
    :silent
  ]

  input do
    field(:worktree, Any)
    field(:mise, Executable)
    field(:target, ToolTarget)
    field(:prefix, StringType)
    field(:all, Boolean, default: false)
    field(:minimum_release_age, StringType)
    field(:no_versions_host, Boolean, default: false)
    field(:prerelease, Boolean, default: false)
    field(:strict_metadata, Boolean, default: false)
    field(:env, StringType)
    field(:jobs, Integer)
    field(:quiet, Boolean, default: false)
    field(:verbose, Integer, default: 0)
    field(:locked, Boolean, default: false)
    field(:silent, Boolean, default: false)
  end

  required([:worktree, :mise])

  @impl Runner
  @spec run(input :: Input.t(), context :: Context.t()) :: Runner.result()
  def run(%Input{worktree: worktree, mise: mise, target: target} = input, %Context{
        node: node_name
      }) do
    with {:ok, worktree_path} <- worktree_path(worktree, node_name) do
      Capabilities.list_available_versions(
        worktree_path,
        mise,
        target,
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
