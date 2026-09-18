defmodule DomovoyMisePlugin.Type.AvailableVersions do
  @moduledoc """
  `DomovoyCore.Type` for rows returned by `mise ls-remote --json`.
  """

  use DomovoyCore.Type

  alias DomovoyCore.Type

  @type version() :: %{
          version: String.t(),
          tool: String.t() | nil,
          created_at: String.t() | nil,
          prerelease: boolean() | nil
        }
  @type t() :: [version()]

  @keys [:version, :tool, :created_at, :prerelease]

  @impl Ecto.Type
  def type, do: :map

  @impl DomovoyCore.Type
  @spec cast(raw :: any(), metadata :: DomovoyCore.Type.metadata()) :: DomovoyCore.Type.cast()
  def cast(versions, _metadata) when is_list(versions) do
    versions
    |> Enum.reduce_while({:ok, []}, fn version, {:ok, cast_versions} ->
      case cast_version(version) do
        {:ok, cast_version} -> {:cont, {:ok, [cast_version | cast_versions]}}
        :error -> {:halt, :error}
      end
    end)
    |> case do
      {:ok, cast_versions} -> {:ok, Enum.reverse(cast_versions)}
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

  @spec cast_version(raw :: any()) :: {:ok, version()} | :error
  defp cast_version(%{
         version: version,
         tool: tool,
         created_at: created_at,
         prerelease: prerelease
       })
       when is_binary(version) and (is_binary(tool) or is_nil(tool)) and
              (is_binary(created_at) or is_nil(created_at)) and
              (is_boolean(prerelease) or is_nil(prerelease)) do
    {:ok, %{version: version, tool: tool, created_at: created_at, prerelease: prerelease}}
  end

  defp cast_version(_raw), do: :error
end
