defmodule DomovoyMisePlugin.Type.ToolTargetTest do
  use ExUnit.Case, async: true

  alias DomovoyMisePlugin.Type.ToolTarget
  alias DomovoyMisePlugin.Type.ToolTargets

  test "accepts Mise short, backend, version, and option target forms" do
    targets = [
      "node",
      "node@24",
      "github:cli/cli@v2.62.0",
      "cargo:ripgrep[features=pcre2]@latest"
    ]

    for target <- targets do
      assert ToolTarget.cast(target) == {:ok, target}
    end

    assert ToolTargets.cast(targets) == {:ok, targets}
  end

  test "rejects blank, option-like, multiline, and non-string targets" do
    for target <- ["", " node@24", "--force", "node\npython", "node\0x", 24] do
      assert ToolTarget.cast(target) == :error
    end

    assert ToolTargets.cast(["node", "--force"]) == :error
    assert ToolTargets.cast("node") == :error
  end
end
