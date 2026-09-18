defmodule DomovoyMisePlugin do
  @moduledoc """
  Mise capabilities, types, and runners for Domovoy.

  The plugin detects Mise, trusts toolchain configuration files, installs
  configured tools, lists available versions, and searches the tool catalog in
  managed worktrees.

  Detection and trust treat Mise as optional. Operations that require Mise
  return a typed error when it is unavailable.
  """
end
