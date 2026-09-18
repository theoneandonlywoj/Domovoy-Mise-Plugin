defmodule DomovoyMisePlugin.Runner.Install do
  @moduledoc """
  Installs the Mise tools configured for a managed worktree.

  With no `targets`, this runs bare `mise install` in the worktree and therefore
  supports `.tool-versions` as well as Mise TOML configuration. Explicit Mise
  targets are accepted without narrowing Mise's target grammar.

  The runner returns the foreign worktree unchanged. The Engine casts it
  through the node output type.
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
  alias DomovoyMisePlugin.Type.ToolTargets

  @option_fields [
    :force,
    :jobs,
    :dry_run,
    :verbose,
    :include_task_tools,
    :include_lazy,
    :minimum_release_age,
    :monorepo,
    :shared,
    :system,
    :env,
    :quiet,
    :locked,
    :silent
  ]

  input do
    field(:worktree, Any)
    field(:mise, Executable)
    field(:targets, ToolTargets, default: [])
    field(:force, Boolean, default: false)
    field(:jobs, Integer)
    field(:dry_run, Boolean, default: false)
    field(:verbose, Integer, default: 0)
    field(:include_task_tools, Boolean, default: false)
    field(:include_lazy, Boolean, default: false)
    field(:minimum_release_age, StringType)
    field(:monorepo, Boolean, default: false)
    field(:shared, StringType)
    field(:system, Boolean, default: false)
    field(:env, StringType)
    field(:quiet, Boolean, default: false)
    field(:locked, Boolean, default: false)
    field(:silent, Boolean, default: false)
  end

  required([:worktree, :mise])

  @impl Runner
  @spec run(input :: Input.t(), context :: Context.t()) :: Runner.result()
  def run(%Input{worktree: worktree, mise: mise, targets: targets} = input, %Context{
        node: node_name
      }) do
    with {:ok, worktree_path} <- worktree_path(worktree, node_name),
         :ok <-
           Capabilities.install_worktree_tools(
             worktree_path,
             mise,
             targets,
             options(input),
             node_name
           ) do
      {:ok, worktree}
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
