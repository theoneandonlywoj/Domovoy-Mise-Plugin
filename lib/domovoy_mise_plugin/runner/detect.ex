defmodule DomovoyMisePlugin.Runner.Detect do
  @moduledoc """
  Finds the Mise executable for a Domovoy workflow.

  Mise is optional. If Mise is not installed, this runner gives an unavailable
  state. It does not give an error, so the workflow can continue.

  ## Inputs

  This runner has no inputs. It reads the `PATH` of the operating system.

  The Engine casts the result through the node output type. Usually that type
  is `DomovoyMisePlugin.Type.Executable`.
  """

  use DomovoyCore.Runner

  alias DomovoyCore.Context
  alias DomovoyCore.Runner
  alias DomovoyMisePlugin.Capabilities

  input do
  end

  @impl Runner
  @spec run(input :: Input.t(), context :: Context.t()) :: Runner.result()
  def run(%Input{}, %Context{}), do: Capabilities.detect_executable()
end
