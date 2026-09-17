defmodule DomovoyMisePlugin.Type.Executable do
  @moduledoc """
  `DomovoyCore.Type` for the Mise executable on this machine.

  The raw value holds `available?` and `executable`. `available?` is `false`
  when the machine has no Mise, and then `executable` is `nil`. This is a
  correct value and not an error. Therefore a workflow continues without Mise.

  ## Examples

  `dump/1` and `load/1` round-trip a value through a document:

      iex> state = %{available?: false, executable: nil}
      iex> {:ok, document} = DomovoyMisePlugin.Type.Executable.dump(state)
      iex> document
      %{"available?" => false, "executable" => nil}
      iex> DomovoyMisePlugin.Type.Executable.load(document)
      {:ok, state}
  """

  use DomovoyCore.Type

  @type state() :: %{available?: boolean(), executable: String.t() | nil}

  @impl Ecto.Type
  def type, do: :map

  @impl DomovoyCore.Type
  @spec cast(raw :: any(), metadata :: DomovoyCore.Type.metadata()) :: DomovoyCore.Type.cast()
  def cast(%{available?: true, executable: executable} = state, _metadata)
      when is_binary(executable),
      do: {:ok, state}

  def cast(%{available?: false, executable: nil} = state, _metadata), do: {:ok, state}
  def cast(_raw, _metadata), do: :error

  @keys [:available?, :executable]

  @impl Ecto.Type
  @spec load(document :: any()) :: {:ok, state()} | :error
  def load(document) when is_map(document),
    do: document |> DomovoyCore.Type.atom_keys(@keys) |> cast()

  def load(_document), do: :error
end
