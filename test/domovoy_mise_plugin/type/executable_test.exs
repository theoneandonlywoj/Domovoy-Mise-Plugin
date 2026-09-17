defmodule DomovoyMisePlugin.Type.ExecutableTest do
  use ExUnit.Case, async: true

  alias DomovoyMisePlugin.Type.Executable, as: ExecutableType

  doctest ExecutableType

  describe "cast/2" do
    test "accepts an available executable with a path" do
      state = %{available?: true, executable: "/opt/homebrew/bin/mise"}

      assert ExecutableType.cast(state, %{}) == {:ok, state}
    end

    test "accepts an unavailable executable without a path" do
      state = %{available?: false, executable: nil}

      assert ExecutableType.cast(state, %{}) == {:ok, state}
    end

    test "refuses an inconsistent state" do
      assert ExecutableType.cast(%{available?: true, executable: nil}, %{}) == :error
      assert ExecutableType.cast(%{available?: false, executable: "/bin/mise"}, %{}) == :error
      assert ExecutableType.cast(%{available?: true}, %{}) == :error
      assert ExecutableType.cast("mise", %{}) == :error
      assert ExecutableType.cast(nil, %{}) == :error
    end
  end

  describe "Ecto.Type" do
    test "is stored as a map" do
      state = %{available?: false, executable: nil}

      assert ExecutableType.type() == :map
      assert ExecutableType.cast(state) == {:ok, state}
      assert {:ok, document} = ExecutableType.dump(state)
      assert ExecutableType.load(document) == {:ok, state}
    end
  end
end
