defmodule DomovoyMisePlugin.Runner.Trust do
  @moduledoc """
  Trusts the Mise toolchain configuration of a managed worktree.

  Mise does not use a new worktree configuration until a person trusts the
  file. This runner performs that step.

  If Mise is not installed, this runner logs a warning and returns the
  worktree. An optional tool must not stop the workflow.

  ## Inputs

    * `worktree` - required. The complete foreign worktree value. It must have
      a binary `:path` field.
    * `mise` - required. The result from `DomovoyMisePlugin.Runner.Detect`.

  `worktree` uses `DomovoyCore.Type.Any`. This plugin reads only the `:path`
  field, so it does not depend on the Git plugin or its worktree type.

  The Engine casts the returned worktree through the node output type.
  """

  use DomovoyCore.Runner

  alias DomovoyCore.Context
  alias DomovoyCore.Runner
  alias DomovoyMisePlugin.Capabilities
  alias DomovoyMisePlugin.Type.Executable

  input do
    field(:worktree, DomovoyCore.Type.Any)
    field(:mise, Executable)
  end

  required([:worktree, :mise])

  @impl Runner
  @spec run(input :: Input.t(), context :: Context.t()) :: Runner.result()
  def run(
        %Input{worktree: %{path: worktree_path} = worktree, mise: mise},
        %Context{node: node_name}
      )
      when is_binary(worktree_path) do
    with :ok <- Capabilities.trust_worktree_configs(worktree_path, mise, node_name) do
      {:ok, worktree}
    end
  end
end
