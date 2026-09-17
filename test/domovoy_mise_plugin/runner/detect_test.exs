defmodule DomovoyMisePlugin.Runner.DetectTest do
  use ExUnit.Case, async: true

  alias DomovoyCore.Context
  alias DomovoyCore.Job
  alias DomovoyCore.Runner
  alias DomovoyMisePlugin.Runner.Detect

  test "declares an empty typed input and returns the installed Mise state" do
    input = Detect |> Runner.changeset(%{}) |> Ecto.Changeset.apply_changes()
    context = %Context{job: Job.new("detect-mise"), node: "detect_mise"}

    assert %Detect.Input{} = input
    assert {:ok, state} = Detect.run(input, context)

    expected =
      case System.find_executable("mise") do
        nil -> %{available?: false, executable: nil}
        executable -> %{available?: true, executable: executable}
      end

    assert state == expected
  end
end
