defmodule DomovoyMisePlugin.Type.SearchMatchTest do
  use ExUnit.Case, async: true

  alias DomovoyMisePlugin.Type.SearchMatch

  test "casts and persists supported match modes" do
    assert SearchMatch.cast(:contains) == {:ok, :contains}
    assert SearchMatch.cast("fuzzy") == {:ok, :fuzzy}
    assert SearchMatch.dump(:equal) == {:ok, "equal"}
    assert SearchMatch.load("contains") == {:ok, :contains}
  end

  test "rejects unsupported modes" do
    assert SearchMatch.cast(:prefix) == :error
    assert SearchMatch.cast("prefix") == :error
  end
end
