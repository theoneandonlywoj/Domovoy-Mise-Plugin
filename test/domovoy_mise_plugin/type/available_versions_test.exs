defmodule DomovoyMisePlugin.Type.AvailableVersionsTest do
  use ExUnit.Case, async: true

  alias DomovoyMisePlugin.Type.AvailableVersions

  test "casts and round-trips normalized version rows" do
    versions = [
      %{
        version: "24.0.0",
        tool: "node",
        created_at: "2025-05-06T00:00:00Z",
        prerelease: false
      },
      %{version: "nightly", tool: nil, created_at: nil, prerelease: nil}
    ]

    assert AvailableVersions.cast(versions) == {:ok, versions}
    assert {:ok, document} = AvailableVersions.dump(versions)
    assert AvailableVersions.load(document) == {:ok, versions}
  end

  test "rejects malformed rows" do
    assert AvailableVersions.cast([%{version: 24}]) == :error
    assert AvailableVersions.cast(%{}) == :error
  end
end
