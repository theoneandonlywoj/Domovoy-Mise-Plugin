defmodule DomovoyMisePlugin.Type.ToolTarget do
  @moduledoc """
  `DomovoyCore.Type` for one Mise tool target.

  Mise supports short names, version requests, explicit backends, and backend
  options. This type deliberately keeps that grammar opaque so new Mise target
  forms do not require a plugin release.
  """

  use DomovoyCore.Type

  @type t() :: String.t()

  @impl Ecto.Type
  def type, do: :string

  @impl DomovoyCore.Type
  @spec cast(raw :: any(), metadata :: DomovoyCore.Type.metadata()) :: DomovoyCore.Type.cast()
  def cast(target, _metadata) when is_binary(target) do
    if valid?(target), do: {:ok, target}, else: :error
  end

  def cast(_raw, _metadata), do: :error

  @spec valid?(target :: String.t()) :: boolean()
  defp valid?(target) do
    target != "" and
      target == String.trim(target) and
      not String.starts_with?(target, "-") and
      not String.contains?(target, ["\0", "\n", "\r"])
  end
end
