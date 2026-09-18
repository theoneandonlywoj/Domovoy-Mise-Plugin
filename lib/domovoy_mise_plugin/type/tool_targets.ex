defmodule DomovoyMisePlugin.Type.ToolTargets do
  @moduledoc """
  `DomovoyCore.Type` for an ordered list of Mise tool targets.
  """

  use DomovoyCore.Type

  alias DomovoyMisePlugin.Type.ToolTarget

  @type t() :: [ToolTarget.t()]

  @impl Ecto.Type
  def type, do: {:array, ToolTarget}

  @impl DomovoyCore.Type
  @spec cast(raw :: any(), metadata :: DomovoyCore.Type.metadata()) :: DomovoyCore.Type.cast()
  def cast(targets, _metadata) when is_list(targets) do
    targets
    |> Enum.reduce_while({:ok, []}, fn target, {:ok, cast_targets} ->
      case ToolTarget.cast(target) do
        {:ok, cast_target} -> {:cont, {:ok, [cast_target | cast_targets]}}
        :error -> {:halt, :error}
      end
    end)
    |> case do
      {:ok, cast_targets} -> {:ok, Enum.reverse(cast_targets)}
      :error -> :error
    end
  end

  def cast(_raw, _metadata), do: :error
end
