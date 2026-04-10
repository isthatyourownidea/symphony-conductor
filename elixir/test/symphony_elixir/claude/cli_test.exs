defmodule SymphonyElixir.Claude.CLITest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Claude.CLI

  describe "build_args/1" do
    test "builds args for a new session" do
      args = CLI.build_args(%{
        prompt: "Fix the bug",
        cwd: "/tmp/workspace",
        session_id: "symphony-PROJ-123-turn-1",
        model: "sonnet",
        permission_mode: "auto",
        allowed_tools: ["Bash", "Read", "Write", "Edit"],
        max_turns: 20
      })

      assert "-p" in args
      assert "Fix the bug" in args
      assert "--output-format" in args
      assert "stream-json" in args
      assert "--session-id" in args
      assert "symphony-PROJ-123-turn-1" in args
      assert "--model" in args
      assert "sonnet" in args
      assert "--permission-mode" in args
      assert "auto" in args
      assert "--allowedTools" in args
      assert "Bash,Read,Write,Edit" in args
      refute "--print" in args
    end

    test "builds args for resume" do
      args = CLI.build_resume_args(%{
        session_id: "symphony-PROJ-123-turn-1",
        prompt: "Address review feedback"
      })

      assert "--resume" in args
      assert "symphony-PROJ-123-turn-1" in args
      assert "-p" in args
      assert "Address review feedback" in args
      assert "--output-format" in args
      assert "stream-json" in args
    end

    test "includes max-turns when specified" do
      args = CLI.build_args(%{
        prompt: "Fix",
        cwd: "/tmp/ws",
        session_id: "test",
        model: "sonnet",
        permission_mode: "auto",
        allowed_tools: [],
        max_turns: 10
      })

      assert "--max-turns" in args
      assert "10" in args
    end

    test "includes max-budget-usd when specified" do
      args = CLI.build_args(%{
        prompt: "Fix",
        cwd: "/tmp/ws",
        session_id: "test",
        model: "sonnet",
        permission_mode: "auto",
        allowed_tools: [],
        max_turns: 20,
        max_budget_usd: 5.0
      })

      assert "--max-budget-usd" in args
      assert "5.0" in args
    end
  end

  describe "session_id/2" do
    test "generates deterministic UUID" do
      id1 = CLI.session_id("PROJ-123", 1)
      id2 = CLI.session_id("PROJ-123", 2)

      # Valid UUID format
      assert id1 =~ ~r/^[0-9a-f]{8}-[0-9a-f]{4}-5[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/
      assert id2 =~ ~r/^[0-9a-f]{8}-[0-9a-f]{4}-5[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/

      # Different turns produce different IDs
      assert id1 != id2

      # Deterministic — same input produces same output
      assert CLI.session_id("PROJ-123", 1) == id1
    end
  end
end
