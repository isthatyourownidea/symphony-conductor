# Symphony Conductor

A fork of [OpenAI's Symphony](https://github.com/openai/symphony) that replaces Codex with [Claude Code](https://docs.anthropic.com/en/docs/claude-code).

Queue issues in Linear before bed. Wake up to PRs.

Symphony Conductor is an Elixir daemon that polls Linear for issues, creates isolated git worktrees, spawns Claude Code sessions with `--permission-mode auto`, and opens pull requests for human review. It includes optional overnight scheduling so your Claude Code plan tokens get used while you sleep.

> [!WARNING]
> Engineering preview. The agent runs autonomously with shell access inside each worktree. Use on trusted repos only.

## What changed from upstream Symphony

Replaced the Codex JSON-RPC protocol (~4,500 lines) with Claude Code CLI invocation (~1,300 lines). Uses `--permission-mode auto` instead of Codex sandbox policies. Generates `CLAUDE.md` and `.mcp.json` per worktree. Added overnight scheduling via cron + `caffeinate` + `pmset`.

## Getting started

This is a reference implementation. Fork it and adapt for your setup.

### What you need

- Elixir 1.19+ / Erlang 28+ — the repo includes a `mise.toml`, so `mise install` in `elixir/` handles this
- Claude Code CLI (`claude`) on your PATH
- A Linear project with states: Todo, In Progress, Human Review, Merging, Rework, Done
- `LINEAR_API_KEY` — [Linear personal API key](https://linear.app/settings/api)
- `GITHUB_TOKEN` — scoped to the repo your agents will work on

### What to configure

Everything lives in `elixir/WORKFLOW.md`. The YAML frontmatter is config, the Markdown body is the prompt template.

**You must change:**
- `tracker.project_slug` — your Linear project identifier
- `hooks.after_create` — the git clone command for the repo agents work on

**You'll probably want to tune:**

| Setting | Default | What it does |
|---------|---------|--------------|
| `agent.max_concurrent_agents` | 3 | How many issues run simultaneously |
| `agent.max_turns` | 15 | Hard cap on turns per issue |
| `claude.model` | sonnet | Model for agent sessions |
| `claude.max_budget_usd` | unset | Per-issue spend cap |
| `claude.allowed_tools` | Bash, Read, Write, Edit, Glob, Grep | Tools available to agents |
| `polling.interval_ms` | 5000 | How often to check Linear |

### Run it

```bash
cd elixir
mix deps.get
export LINEAR_API_KEY="lin_api_..."
export GITHUB_TOKEN="ghp_..."
mix run --no-halt
```

Create an issue in Linear, move it to "Todo", and watch. The daemon picks it up within one poll interval.

## Overnight mode

The included `conductor.sh` wraps the daemon for unattended overnight runs. It starts `caffeinate` to keep the Mac awake with the lid closed (requires AC power).

```bash
./conductor.sh start    # start daemon + caffeinate
./conductor.sh stop     # graceful shutdown
./conductor.sh status   # check if running
```

For fully automatic nightly runs:

```bash
# Wake Mac at 10:50pm every night (works lid-closed, plugged in, even powered off)
sudo pmset repeat wakeorpoweron MTWRFSU 22:50:00

# Start conductor at 11pm, stop at 6am
crontab -e
# 0 23 * * * /path/to/conductor.sh start >> /path/to/cron.log 2>&1
# 0 6  * * * /path/to/conductor.sh stop >> /path/to/cron.log 2>&1
```

Queue issues during the day. Plug in your laptop. Go to sleep. PRs in the morning.

## How it works

1. Daemon polls Linear every 5s for issues in active states
2. For each issue, creates an isolated git worktree
3. Generates `CLAUDE.md` (issue context + rules), `.mcp.json` (Linear MCP), `.claude/settings.json` (permissions)
4. Spawns `claude -p "..." --permission-mode auto --output-format stream-json`
5. Streams events to the terminal dashboard
6. Agent works the issue: reads code, makes changes, runs tests, opens a PR
7. If the issue is still active after the session, resumes with `claude --resume`
8. You review the PR in the morning, approve or request rework in Linear

## Security

Three layers:

1. **PR gate** — agents open PRs, humans merge. Nothing lands without review.
2. **Worktree isolation** — each issue gets its own clone. Agents can't access other worktrees or the host filesystem.
3. **Auto mode** — Claude Code's built-in policy engine blocks destructive operations (force push, credential exfiltration, pushing to main, `rm -rf` on pre-existing files) while allowing normal development work.

## Project structure

```
conductor.sh           start/stop wrapper with caffeinate
elixir/
  WORKFLOW.md          prompt template + config (start here)
  lib/symphony_elixir/
    claude/cli.ex      spawns claude CLI as Elixir Port
    claude/output_parser.ex   parses stream-json output
    agent_runner.ex    orchestrates per-issue sessions
    orchestrator.ex    polling loop, dispatch, concurrency
    workspace.ex       worktree lifecycle + CLAUDE.md generation
    config/schema.ex   typed config from WORKFLOW.md
  test/                tests (mix test)
SPEC.md                upstream Symphony specification
LICENSE                Apache 2.0 (upstream)
NOTICE                 OpenAI copyright
```

## Attribution

Fork of [OpenAI Symphony](https://github.com/openai/symphony), Apache 2.0. Original LICENSE and NOTICE preserved.
