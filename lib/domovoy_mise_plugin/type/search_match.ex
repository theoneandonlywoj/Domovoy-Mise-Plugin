defmodule DomovoyMisePlugin.Type.SearchMatch do
  @moduledoc """
  `DomovoyCore.Type` for Mise's search match mode.
  """

  use DomovoyCore.Type

  @modes [:equal, :contains, :fuzzy]

  @type t() :: :equal | :contains | :fuzzy

  @impl Ecto.Type
  def type, do: :string

  @impl DomovoyCore.Type
  @spec cast(raw :: any(), metadata :: DomovoyCore.Type.metadata()) :: DomovoyCore.Type.cast()
  def cast(mode, _metadata) when mode in @modes, do: {:ok, mode}

  def cast(mode, _metadata) when is_binary(mode) do
    case Enum.find(@modes, &(Atom.to_string(&1) == mode)) do
      nil -> :error
      cast_mode -> {:ok, cast_mode}
    end
  end

  def cast(_raw, _metadata), do: :error

  @impl Ecto.Type
  @spec dump(mode :: t()) :: {:ok, String.t()} | :error
  def dump(mode) when mode in @modes, do: {:ok, Atom.to_string(mode)}
  def dump(_mode), do: :error

  @impl Ecto.Type
  @spec load(document :: any()) :: {:ok, t()} | :error
  def load(document), do: cast(document)
end
