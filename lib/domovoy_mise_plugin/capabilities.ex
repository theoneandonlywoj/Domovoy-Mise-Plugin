defmodule DomovoyMisePlugin.Capabilities do
  @moduledoc """
  Provides the Mise operations that Domovoy runners use.

  Mise reads a project toolchain from a root configuration file. A new
  worktree can contain such a file, but Mise does not trust it yet. This module
  finds Mise and trusts each supported root configuration file.

  Mise is optional. If Mise is not installed, the trust operation logs a
  warning and succeeds.

  ## Examples

      iex> DomovoyMisePlugin.Capabilities.trust_failed_error(
      ...>   "command exited with status 1",
      ...>   "/repo/mise.toml",
      ...>   "trust_mise"
      ...> )
      %DomovoyCore.Error{
        type: :mise_trust_failed,
        reason: "command exited with status 1",
        metadata: %{
          command: ["mise", "trust", "/repo/mise.toml"],
          node_name: "trust_mise",
          field_name: :mise
        }
      }
  """

  require Logger

  alias DomovoyCore.Error
  alias DomovoyCore.Shell

  @typedoc "The detected state of the Mise executable."
  @type executable_state() :: %{available?: boolean(), executable: String.t() | nil}

  @typedoc "The result of a `mise trust` command."
  @type trust_result() :: {:ok, String.t()} | {:error, String.t()}

  @config_files ["mise.toml", ".mise.toml", ".tool-versions"]
  @mise_timeout 30_000

  @doc """
  Detects the Mise executable on the system `PATH`.

  If Mise is not present, this function gives an unavailable state. It does not
  give an error.
  """
  @spec detect_executable() :: {:ok, executable_state()}
  def detect_executable do
    case System.find_executable("mise") do
      nil -> {:ok, %{available?: false, executable: nil}}
      executable -> {:ok, %{available?: true, executable: executable}}
    end
  end

  @doc """
  Trusts each supported root Mise configuration file in `worktree_path`.

  The function checks `mise.toml`, `.mise.toml`, and `.tool-versions` in that
  order. It stops after the first failed command.

  If Mise is unavailable, this function logs a warning and gives `:ok`.
  """
  @spec trust_worktree_configs(
          worktree_path :: String.t(),
          mise :: executable_state(),
          node_name :: String.t() | nil
        ) :: :ok | {:error, Error.t()}
  def trust_worktree_configs(worktree_path, %{available?: false}, _node_name)
      when is_binary(worktree_path) do
    Logger.warning("Mise is not installed; skipping worktree toolchain trust")
    :ok
  end

  def trust_worktree_configs(
        worktree_path,
        %{available?: true, executable: executable},
        node_name
      )
      when is_binary(worktree_path) and is_binary(executable) do
    worktree_path
    |> config_paths()
    |> Enum.reduce_while(:ok, fn config_path, :ok ->
      case trust_result(executable, config_path, worktree_path) do
        {:ok, _output} ->
          {:cont, :ok}

        {:error, reason} ->
          {:halt, {:error, trust_failed_error(reason, config_path, node_name)}}
      end
    end)
  end

  @doc """
  Returns absolute paths for supported root Mise configuration files.

  The result contains only regular files. It keeps the supported file order.
  """
  @spec config_paths(worktree_path :: String.t()) :: [String.t()]
  def config_paths(worktree_path) when is_binary(worktree_path) do
    @config_files
    |> Enum.map(fn config_file -> Path.join(worktree_path, config_file) end)
    |> Enum.filter(fn path -> File.regular?(path) end)
  end

  @doc """
  Runs `mise trust <config_path>` in `cwd`.
  """
  @spec trust_result(executable :: String.t(), config_path :: String.t(), cwd :: String.t()) ::
          trust_result()
  def trust_result(executable, config_path, cwd)
      when is_binary(executable) and is_binary(config_path) and is_binary(cwd) do
    Shell.run(executable, ["trust", config_path], cd: cwd, timeout: @mise_timeout)
  end

  @doc """
  Builds an error for a failed `mise trust` command.

  `reason` is the message from `DomovoyCore.Shell`. The error identifies the node
  and the `mise` input without retaining input values.

  ## Examples

      iex> error = DomovoyMisePlugin.Capabilities.trust_failed_error(
      ...>   "command timed out",
      ...>   "/repo/mise.toml",
      ...>   "trust_mise"
      ...> )
      iex> {error.type, error.reason, error.metadata.node_name}
      {:mise_trust_failed, "command timed out", "trust_mise"}
  """
  @spec trust_failed_error(
          reason :: String.t(),
          config_path :: String.t(),
          node_name :: String.t() | nil
        ) :: Error.t()
  def trust_failed_error(reason, config_path, node_name) do
    %Error{
      type: :mise_trust_failed,
      reason: reason,
      metadata: %{
        command: ["mise", "trust", config_path],
        node_name: node_name,
        field_name: :mise
      }
    }
  end
end
