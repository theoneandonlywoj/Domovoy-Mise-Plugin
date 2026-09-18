defmodule DomovoyMisePlugin.Type.SearchResultsTest do
  use ExUnit.Case, async: true

  alias DomovoyMisePlugin.Type.SearchResults

  test "casts and round-trips structured search rows" do
    results = [
      %{name: "jq", description: "Command-line JSON processor"},
      %{name: "gojq", description: ""}
    ]

    assert SearchResults.cast(results) == {:ok, results}
    assert {:ok, document} = SearchResults.dump(results)
    assert SearchResults.load(document) == {:ok, results}
  end

  test "rejects empty names and malformed rows" do
    assert SearchResults.cast([%{name: "", description: "missing"}]) == :error
    assert SearchResults.cast([%{name: "jq"}]) == :error
  end
end
