defmodule SymphonyElixir.WorkspaceClaudeTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Workspace

  @tmp_dir System.tmp_dir!()

  setup do
    workspace = Path.join(@tmp_dir, "test_workspace_#{:rand.uniform(100_000)}")
    File.mkdir_p!(workspace)
    on_exit(fn -> File.rm_rf!(workspace) end)
    {:ok, workspace: workspace}
  end

  describe "generate_claude_md/3" do
    test "writes CLAUDE.md with issue context", %{workspace: workspace} do
      issue = %{
        identifier: "PROJ-123",
        title: "Fix authentication timeout",
        description: "Users are getting logged out after 5 minutes",
        state: "In Progress"
      }

      Workspace.generate_claude_md(workspace, issue, "Do your best work.")

      claude_md = File.read!(Path.join(workspace, "CLAUDE.md"))
      assert claude_md =~ "PROJ-123"
      assert claude_md =~ "Fix authentication timeout"
      assert claude_md =~ "Users are getting logged out"
      assert claude_md =~ "In Progress"
      assert claude_md =~ "Do your best work."
    end
  end

  describe "generate_mcp_json/2" do
    test "writes .mcp.json with Linear MCP config", %{workspace: workspace} do
      Workspace.generate_mcp_json(workspace, "lin_api_test_token")

      mcp = workspace |> Path.join(".mcp.json") |> File.read!() |> Jason.decode!()
      assert mcp["mcpServers"]["linear"]
    end
  end

  describe "generate_claude_settings/2" do
    test "writes .claude/settings.json", %{workspace: workspace} do
      Workspace.generate_claude_settings(workspace, ["Bash(npm test *)"])

      settings_path = Path.join([workspace, ".claude", "settings.json"])
      assert File.exists?(settings_path)
      settings = settings_path |> File.read!() |> Jason.decode!()
      assert "Bash(npm test *)" in settings["permissions"]["allow"]
    end
  end
end
