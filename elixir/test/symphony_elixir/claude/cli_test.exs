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
      assert "--print" in args
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
    test "generates deterministic session ID" do
      assert CLI.session_id("PROJ-123", 1) == "symphony-PROJ-123-turn-1"
      assert CLI.session_id("PROJ-123", 2) == "symphony-PROJ-123-turn-2"
    end
  end
end
