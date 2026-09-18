defmodule DomovoyMisePlugin.Capabilities do
  @moduledoc """
  Provides the Mise operations that Domovoy runners use.

  Mise reads a project toolchain from root configuration files. This module
  finds Mise, trusts supported configuration files, installs tools, lists
  available versions, and searches the tool catalog.

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
  alias DomovoyMisePlugin.Type.ToolTarget

  @typedoc "The detected state of the Mise executable."
  @type executable_state() :: %{available?: boolean(), executable: String.t() | nil}

  @typedoc "The result of a `mise trust` command."
  @type trust_result() :: {:ok, String.t()} | {:error, String.t()}

  @typedoc "Options accepted by a Mise capability."
  @type options() :: %{optional(atom()) => term()}

  @typedoc "One available Mise version."
  @type available_version() :: %{
          version: String.t(),
          tool: String.t() | nil,
          created_at: String.t() | nil,
          prerelease: boolean() | nil
        }

  @typedoc "One structured Mise search result."
  @type search_result() :: %{name: String.t(), description: String.t()}

  @config_files ["mise.toml", ".mise.toml", ".tool-versions"]
  @trust_timeout 30_000
  @install_timeout 1_800_000
  @list_versions_timeout 120_000
  @search_timeout 30_000

  @common_boolean_options [:quiet, :locked, :silent]
  @install_boolean_options [
    :force,
    :dry_run,
    :include_task_tools,
    :include_lazy,
    :monorepo,
    :system
  ]
  @list_boolean_options [:all, :no_versions_host, :prerelease, :strict_metadata]

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
  Reads the path from a foreign worktree value.

  Both atom and string keys are accepted because `DomovoyCore.Type.Any`
  persists atom map keys as strings.
  """
  @spec worktree_path(worktree :: any()) :: {:ok, String.t()} | :error
  def worktree_path(%{path: path}) when is_binary(path), do: {:ok, path}
  def worktree_path(%{"path" => path}) when is_binary(path), do: {:ok, path}
  def worktree_path(_worktree), do: :error

  @doc "Builds an error for a foreign worktree value without a binary path."
  @spec invalid_worktree_error(node_name :: String.t() | nil) :: Error.t()
  def invalid_worktree_error(node_name) do
    %Error{
      type: :mise_invalid_worktree,
      reason: %{required_field: :path},
      metadata: %{node_name: node_name, field_name: :worktree}
    }
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
    Shell.run(executable, ["trust", config_path], cd: cwd, timeout: @trust_timeout)
  end

  @doc """
  Installs configured or explicitly targeted tools in a worktree.

  An empty target list runs bare `mise install`, so Mise loads `.tool-versions`,
  Mise TOML files, and its normal active configuration hierarchy.
  """
  @spec install_worktree_tools(
          worktree_path :: String.t(),
          mise :: executable_state(),
          targets :: [String.t()],
          options :: options(),
          node_name :: String.t() | nil
        ) :: :ok | {:error, Error.t()}
  def install_worktree_tools(
        worktree_path,
        %{available?: false},
        _targets,
        _options,
        node_name
      )
      when is_binary(worktree_path) do
    {:error, unavailable_error(:install, node_name)}
  end

  def install_worktree_tools(
        worktree_path,
        %{available?: true, executable: executable},
        targets,
        options,
        node_name
      )
      when is_binary(worktree_path) and is_binary(executable) do
    with {:ok, args} <- install_args(targets, options, node_name),
         {:ok, _output} <-
           Shell.run(executable, args, cd: worktree_path, timeout: @install_timeout) do
      :ok
    else
      {:error, %Error{} = error} -> {:error, error}
      {:error, reason} -> {:error, command_failed_error(:install, reason, node_name)}
    end
  end

  @doc """
  Lists versions available for one target, or all known tools.

  The command always uses Mise's JSON output and returns normalized rows in
  Mise's backend-defined order.
  """
  @spec list_available_versions(
          worktree_path :: String.t(),
          mise :: executable_state(),
          target :: String.t() | nil,
          options :: options(),
          node_name :: String.t() | nil
        ) :: {:ok, [available_version()]} | {:error, Error.t()}
  def list_available_versions(
        worktree_path,
        %{available?: false},
        _target,
        _options,
        node_name
      )
      when is_binary(worktree_path) do
    {:error, unavailable_error(:list_versions, node_name)}
  end

  def list_available_versions(
        worktree_path,
        %{available?: true, executable: executable},
        target,
        options,
        node_name
      )
      when is_binary(worktree_path) and is_binary(executable) do
    with {:ok, args} <- list_versions_args(target, options, node_name),
         {:ok, output} <-
           Shell.run(executable, args, cd: worktree_path, timeout: @list_versions_timeout),
         {:ok, versions} <- decode_versions(output, node_name) do
      {:ok, versions}
    else
      {:error, %Error{} = error} -> {:error, error}
      {:error, reason} -> {:error, command_failed_error(:list_versions, reason, node_name)}
    end
  end

  @doc """
  Searches Mise's registry and installed backend catalogs.

  Output from `mise search --no-header` is normalized to name and description
  rows. `match_type` is `:contains`, `:equal`, or `:fuzzy`.
  """
  @spec search_tools(
          worktree_path :: String.t(),
          mise :: executable_state(),
          query :: String.t(),
          match_type :: :contains | :equal | :fuzzy,
          options :: options(),
          node_name :: String.t() | nil
        ) :: {:ok, [search_result()]} | {:error, Error.t()}
  def search_tools(
        worktree_path,
        %{available?: false},
        _query,
        _match_type,
        _options,
        node_name
      )
      when is_binary(worktree_path) do
    {:error, unavailable_error(:search, node_name)}
  end

  def search_tools(
        worktree_path,
        %{available?: true, executable: executable},
        query,
        match_type,
        options,
        node_name
      )
      when is_binary(worktree_path) and is_binary(executable) do
    with {:ok, args} <- search_args(query, match_type, options, node_name),
         {:ok, output} <-
           Shell.run(executable, args, cd: worktree_path, timeout: @search_timeout),
         {:ok, results} <- decode_search_results(output, node_name) do
      {:ok, results}
    else
      {:error, %Error{} = error} -> {:error, error}
      {:error, reason} -> {:error, command_failed_error(:search, reason, node_name)}
    end
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

  @spec install_args([String.t()], options(), String.t() | nil) ::
          {:ok, [String.t()]} | {:error, Error.t()}
  defp install_args(targets, options, node_name) when is_map(options) do
    with :ok <- validate_targets(targets),
         :ok <- validate_options(options, @install_boolean_options),
         :ok <- validate_install_options(options) do
      args =
        ["install", "--yes"]
        |> append_flag("--force", option(options, :force, false))
        |> append_flag("--dry-run", option(options, :dry_run, false))
        |> append_flag("--include-task-tools", option(options, :include_task_tools, false))
        |> append_flag("--include-lazy", option(options, :include_lazy, false))
        |> append_option("--minimum-release-age", option(options, :minimum_release_age))
        |> append_flag("--monorepo", option(options, :monorepo, false))
        |> append_option("--shared", option(options, :shared))
        |> append_flag("--system", option(options, :system, false))
        |> append_common_options(options)

      {:ok, args ++ targets}
    else
      {:error, cause} -> {:error, invalid_options_error(:install, cause, node_name)}
    end
  end

  defp install_args(_targets, _options, node_name),
    do: {:error, invalid_options_error(:install, :options_not_a_map, node_name)}

  @spec list_versions_args(String.t() | nil, options(), String.t() | nil) ::
          {:ok, [String.t()]} | {:error, Error.t()}
  defp list_versions_args(target, options, node_name) when is_map(options) do
    with :ok <- validate_optional_target(target),
         :ok <- validate_options(options, @list_boolean_options),
         :ok <- validate_list_options(target, options) do
      args =
        ["ls-remote", "--json"]
        |> append_flag("--all", option(options, :all, false))
        |> append_option("--minimum-release-age", option(options, :minimum_release_age))
        |> append_flag("--no-versions-host", option(options, :no_versions_host, false))
        |> append_flag("--prerelease", option(options, :prerelease, false))
        |> append_flag("--strict-metadata", option(options, :strict_metadata, false))
        |> append_common_options(options)
        |> append_value(target)
        |> append_value(option(options, :prefix))

      {:ok, args}
    else
      {:error, cause} -> {:error, invalid_options_error(:list_versions, cause, node_name)}
    end
  end

  defp list_versions_args(_target, _options, node_name),
    do: {:error, invalid_options_error(:list_versions, :options_not_a_map, node_name)}

  @spec search_args(String.t(), atom(), options(), String.t() | nil) ::
          {:ok, [String.t()]} | {:error, Error.t()}
  defp search_args(query, match_type, options, node_name) when is_map(options) do
    with :ok <- validate_argument(query, :query),
         true <- match_type in [:equal, :contains, :fuzzy],
         :ok <- validate_options(options, []) do
      args =
        ["search", "--match-type", Atom.to_string(match_type), "--no-header"]
        |> append_common_options(options)
        |> append_value(query)

      {:ok, args}
    else
      false -> {:error, invalid_options_error(:search, :invalid_match_type, node_name)}
      {:error, cause} -> {:error, invalid_options_error(:search, cause, node_name)}
    end
  end

  defp search_args(_query, _match_type, _options, node_name),
    do: {:error, invalid_options_error(:search, :options_not_a_map, node_name)}

  @spec validate_targets(any()) :: :ok | {:error, atom()}
  defp validate_targets(targets) when is_list(targets) do
    if Enum.all?(targets, &valid_target?(&1)), do: :ok, else: {:error, :invalid_target}
  end

  defp validate_targets(_targets), do: {:error, :targets_not_a_list}

  @spec validate_optional_target(any()) :: :ok | {:error, atom()}
  defp validate_optional_target(nil), do: :ok
  defp validate_optional_target(target), do: validate_argument(target, :target)

  @spec valid_target?(any()) :: boolean()
  defp valid_target?(target) do
    match?({:ok, _target}, ToolTarget.cast(target))
  end

  @spec validate_options(options(), [atom()]) :: :ok | {:error, atom()}
  defp validate_options(options, operation_boolean_options) do
    boolean_options = @common_boolean_options ++ operation_boolean_options

    cond do
      Enum.any?(boolean_options, fn name ->
        value = option(options, name, false)
        not is_boolean(value)
      end) ->
        {:error, :invalid_boolean_option}

      not valid_optional_positive_integer?(option(options, :jobs)) ->
        {:error, :invalid_jobs}

      not valid_non_negative_integer?(option(options, :verbose, 0)) ->
        {:error, :invalid_verbose}

      not valid_optional_argument?(option(options, :env)) ->
        {:error, :invalid_env}

      true ->
        :ok
    end
  end

  @spec validate_install_options(options()) :: :ok | {:error, atom()}
  defp validate_install_options(options) do
    cond do
      not valid_optional_argument?(option(options, :minimum_release_age)) ->
        {:error, :invalid_minimum_release_age}

      not valid_optional_argument?(option(options, :shared)) ->
        {:error, :invalid_shared_path}

      option(options, :system, false) and not is_nil(option(options, :shared)) ->
        {:error, :shared_conflicts_with_system}

      true ->
        :ok
    end
  end

  @spec validate_list_options(String.t() | nil, options()) :: :ok | {:error, atom()}
  defp validate_list_options(target, options) do
    all? = option(options, :all, false)
    prefix = option(options, :prefix)

    with :ok <- validate_optional_argument(prefix, :invalid_prefix),
         :ok <-
           validate_optional_argument(
             option(options, :minimum_release_age),
             :invalid_minimum_release_age
           ),
         :ok <- validate_all_target(all?, target, prefix),
         :ok <- validate_target_present(all?, target) do
      validate_strict_metadata(
        option(options, :strict_metadata, false),
        option(options, :no_versions_host, false)
      )
    end
  end

  @spec validate_optional_argument(any(), atom()) :: :ok | {:error, atom()}
  defp validate_optional_argument(argument, error) do
    if valid_optional_argument?(argument), do: :ok, else: {:error, error}
  end

  @spec validate_all_target(boolean(), String.t() | nil, String.t() | nil) ::
          :ok | {:error, :all_conflicts_with_target}
  defp validate_all_target(true, target, prefix) when not is_nil(target) or not is_nil(prefix),
    do: {:error, :all_conflicts_with_target}

  defp validate_all_target(_all?, _target, _prefix), do: :ok

  @spec validate_target_present(boolean(), String.t() | nil) ::
          :ok | {:error, :target_required}
  defp validate_target_present(false, nil), do: {:error, :target_required}
  defp validate_target_present(_all?, _target), do: :ok

  @spec validate_strict_metadata(boolean(), boolean()) ::
          :ok | {:error, :strict_metadata_requires_no_versions_host}
  defp validate_strict_metadata(true, false),
    do: {:error, :strict_metadata_requires_no_versions_host}

  defp validate_strict_metadata(_strict_metadata?, _no_versions_host?), do: :ok

  @spec validate_argument(any(), atom()) :: :ok | {:error, atom()}
  defp validate_argument(argument, name) when is_binary(argument) do
    valid? =
      argument != "" and argument == String.trim(argument) and
        not String.starts_with?(argument, "-") and
        not String.contains?(argument, ["\0", "\n", "\r"])

    if valid?, do: :ok, else: {:error, invalid_argument_reason(name)}
  end

  defp validate_argument(_argument, name), do: {:error, invalid_argument_reason(name)}

  @spec invalid_argument_reason(atom()) :: atom()
  defp invalid_argument_reason(:query), do: :invalid_query
  defp invalid_argument_reason(:target), do: :invalid_target

  @spec valid_optional_argument?(any()) :: boolean()
  defp valid_optional_argument?(nil), do: true

  defp valid_optional_argument?(argument) when is_binary(argument) do
    argument != "" and argument == String.trim(argument) and
      not String.contains?(argument, ["\0", "\n", "\r"])
  end

  defp valid_optional_argument?(_argument), do: false

  @spec valid_optional_positive_integer?(any()) :: boolean()
  defp valid_optional_positive_integer?(nil), do: true
  defp valid_optional_positive_integer?(integer), do: is_integer(integer) and integer > 0

  @spec valid_non_negative_integer?(any()) :: boolean()
  defp valid_non_negative_integer?(integer), do: is_integer(integer) and integer >= 0

  @spec append_common_options([String.t()], options()) :: [String.t()]
  defp append_common_options(args, options) do
    args
    |> append_option("--env", option(options, :env))
    |> append_option("--jobs", option(options, :jobs))
    |> append_flag("--quiet", option(options, :quiet, false))
    |> append_verbosity(option(options, :verbose, 0))
    |> append_flag("--locked", option(options, :locked, false))
    |> append_flag("--silent", option(options, :silent, false))
  end

  @spec append_flag([String.t()], String.t(), boolean()) :: [String.t()]
  defp append_flag(args, flag, true), do: args ++ [flag]
  defp append_flag(args, _flag, false), do: args

  @spec append_option([String.t()], String.t(), term()) :: [String.t()]
  defp append_option(args, _flag, nil), do: args
  defp append_option(args, flag, value), do: args ++ [flag, to_string(value)]

  @spec append_verbosity([String.t()], non_neg_integer()) :: [String.t()]
  defp append_verbosity(args, verbosity), do: args ++ List.duplicate("--verbose", verbosity)

  @spec append_value([String.t()], String.t() | nil) :: [String.t()]
  defp append_value(args, nil), do: args
  defp append_value(args, value), do: args ++ [value]

  @spec option(options(), atom(), term()) :: term()
  defp option(options, name, default \\ nil), do: Map.get(options, name, default)

  @spec decode_versions(String.t(), String.t() | nil) ::
          {:ok, [available_version()]} | {:error, Error.t()}
  defp decode_versions(output, node_name) when is_binary(output) do
    with {:ok, versions} when is_list(versions) <- Jason.decode(output),
         {:ok, normalized} <- normalize_versions(versions) do
      {:ok, normalized}
    else
      _error -> {:error, invalid_output_error(:list_versions, node_name)}
    end
  end

  @spec normalize_versions([map()]) :: {:ok, [available_version()]} | :error
  defp normalize_versions(versions) do
    versions
    |> Enum.reduce_while({:ok, []}, fn version, {:ok, normalized} ->
      case normalize_version(version) do
        {:ok, row} -> {:cont, {:ok, [row | normalized]}}
        :error -> {:halt, :error}
      end
    end)
    |> case do
      {:ok, normalized} -> {:ok, Enum.reverse(normalized)}
      :error -> :error
    end
  end

  @spec normalize_version(any()) :: {:ok, available_version()} | :error
  defp normalize_version(%{"version" => version} = row) when is_binary(version) do
    tool = Map.get(row, "tool")
    created_at = Map.get(row, "created_at")
    prerelease = Map.get(row, "prerelease")

    if (is_binary(tool) or is_nil(tool)) and
         (is_binary(created_at) or is_nil(created_at)) and
         (is_boolean(prerelease) or is_nil(prerelease)) do
      {:ok, %{version: version, tool: tool, created_at: created_at, prerelease: prerelease}}
    else
      :error
    end
  end

  defp normalize_version(_row), do: :error

  @spec decode_search_results(String.t(), String.t() | nil) ::
          {:ok, [search_result()]} | {:error, Error.t()}
  defp decode_search_results(output, node_name) when is_binary(output) do
    output
    |> String.split("\n", trim: true)
    |> Enum.reduce_while({:ok, []}, fn line, {:ok, results} ->
      case String.split(String.trim(line), ~r/\s{2,}/, parts: 2) do
        [name, description] when name != "" ->
          {:cont, {:ok, [%{name: name, description: description} | results]}}

        [name] when name != "" ->
          {:cont, {:ok, [%{name: name, description: ""} | results]}}

        _malformed ->
          {:halt, {:error, invalid_output_error(:search, node_name)}}
      end
    end)
    |> case do
      {:ok, results} -> {:ok, Enum.reverse(results)}
      {:error, %Error{} = error} -> {:error, error}
    end
  end

  @spec unavailable_error(atom(), String.t() | nil) :: Error.t()
  defp unavailable_error(operation, node_name) do
    %Error{
      type: :mise_unavailable,
      reason: "Mise is not installed",
      metadata: %{operation: operation, node_name: node_name, field_name: :mise}
    }
  end

  @spec command_failed_error(atom(), String.t(), String.t() | nil) :: Error.t()
  defp command_failed_error(operation, reason, node_name) do
    %Error{
      type: error_type(operation),
      reason: reason,
      metadata: %{
        command: ["mise", subcommand(operation)],
        node_name: node_name,
        field_name: :mise
      }
    }
  end

  @spec invalid_options_error(atom(), atom(), String.t() | nil) :: Error.t()
  defp invalid_options_error(operation, cause, node_name) do
    %Error{
      type: :mise_invalid_options,
      reason: %{operation: operation, cause: cause},
      metadata: %{node_name: node_name, field_name: :mise}
    }
  end

  @spec invalid_output_error(atom(), String.t() | nil) :: Error.t()
  defp invalid_output_error(operation, node_name) do
    %Error{
      type: :mise_invalid_output,
      reason: %{operation: operation},
      metadata: %{node_name: node_name, field_name: :mise}
    }
  end

  @spec error_type(atom()) :: atom()
  defp error_type(:install), do: :mise_install_failed
  defp error_type(:list_versions), do: :mise_list_versions_failed
  defp error_type(:search), do: :mise_search_failed

  @spec subcommand(atom()) :: String.t()
  defp subcommand(:install), do: "install"
  defp subcommand(:list_versions), do: "ls-remote"
  defp subcommand(:search), do: "search"
end
