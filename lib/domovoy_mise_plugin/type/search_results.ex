defmodule DomovoyMisePlugin.Type.SearchResults do
  @moduledoc """
  `DomovoyCore.Type` for structured rows returned by `mise search`.
  """

  use DomovoyCore.Type

  alias DomovoyCore.Type

  @type result() :: %{name: String.t(), description: String.t()}
  @type t() :: [result()]

  @keys [:name, :description]

  @impl Ecto.Type
  def type, do: :map

  @impl DomovoyCore.Type
  @spec cast(raw :: any(), metadata :: DomovoyCore.Type.metadata()) :: DomovoyCore.Type.cast()
  def cast(results, _metadata) when is_list(results) do
    results
    |> Enum.reduce_while({:ok, []}, fn result, {:ok, cast_results} ->
      case cast_result(result) do
        {:ok, cast_result} -> {:cont, {:ok, [cast_result | cast_results]}}
        :error -> {:halt, :error}
      end
    end)
    |> case do
      {:ok, cast_results} -> {:ok, Enum.reverse(cast_results)}
      :error -> :error
    end
  end

  def cast(_raw, _metadata), do: :error

  @impl Ecto.Type
  @spec load(document :: any()) :: {:ok, t()} | :error
  def load(document) when is_list(document) do
    document
    |> Enum.map(&Type.atom_keys(&1, @keys))
    |> cast()
  end

  def load(_document), do: :error

  @spec cast_result(raw :: any()) :: {:ok, result()} | :error
  defp cast_result(%{name: name, description: description})
       when is_binary(name) and name != "" and is_binary(description) do
    {:ok, %{name: name, description: description}}
  end

  defp cast_result(_raw), do: :error
end
