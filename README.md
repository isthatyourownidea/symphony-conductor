# Symphony Conductor

A fork of [OpenAI's Symphony](https://github.com/openai/symphony) that replaces Codex with [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code).

Symphony Conductor is an overnight autonomous coding daemon. It polls Linear for issues, creates isolated git worktrees, spawns Claude Code sessions, and opens PRs for review. You queue work in Linear before bed; PRs are waiting in the morning.

> [!WARNING]
> This is an engineering preview for trusted environments. The agent runs with `--permission-mode auto` and full shell access inside each worktree.

## How it differs from upstream Symphony

- Replaced Codex JSON-RPC protocol with Claude Code CLI invocation (~1,300 lines added, ~4,500 deleted)
- Uses `--permission-mode auto` instead of Codex sandbox/approval policies
- Generates `CLAUDE.md` and `.mcp.json` per worktree (Linear MCP, GitHub MCP)
- Includes overnight scheduling via cron + `caffeinate` + `pmset`
- Prompt template in `WORKFLOW.md` tuned for Claude Code's tool-use patterns

## Prerequisites

- **Elixir 1.19+** (via [mise](https://mise.jdx.dev/) -- `mise install` in `elixir/`)
- **Claude Code CLI** (`claude`) on `$PATH`
- **Linear API key** (`LINEAR_API_KEY` env var)
- **GitHub token** (`GITHUB_TOKEN` or `gh auth` session)

## Quick start

```bash
git clone https://github.com/isthatyourownidea/symphony-conductor.git
cd symphony-conductor/elixir
mise install
mix deps.get

# Configure your project
cp WORKFLOW.md WORKFLOW.md.bak
# Edit WORKFLOW.md: set project_slug, git clone URL, model, concurrency

# Set env vars
export LINEAR_API_KEY="lin_api_..."
export ANTHROPIC_API_KEY="sk-ant-..."

# Run
mix run --no-halt
```

## Configuration

All configuration lives in `elixir/WORKFLOW.md` as YAML frontmatter:

| Setting | Default | Description |
|---------|---------|-------------|
| `tracker.project_slug` | -- | Your Linear project slug |
| `agent.max_concurrent_agents` | 3 | Parallel agent sessions |
| `claude.model` | `sonnet` | Claude model (`sonnet`, `opus`, etc.) |
| `claude.permission_mode` | `auto` | Always `auto` for unattended use |
| `claude.max_turns` | 20 | Max tool-use turns per session |
| `claude.allowed_tools` | Bash, Read, Write, Edit, Glob, Grep | Tools available to the agent |
| `hooks.after_create` | -- | Shell script run after worktree creation |
| `hooks.before_remove` | -- | Shell script run before worktree cleanup |

The Markdown body below the frontmatter is the prompt template, rendered per issue with Liquid (`{{ issue.title }}`, etc.).

## Overnight mode

The included `conductor.sh` wraps the daemon for overnight runs:

```bash
./conductor.sh start   # starts daemon + caffeinate (7h keep-awake)
./conductor.sh stop    # graceful shutdown
./conductor.sh status  # check if running + tail logs
```

For fully unattended nightly runs, combine with cron and `pmset`:

```bash
# Wake Mac at 11pm, start conductor
sudo pmset repeat wakeorpoweron MTWRFSU 23:00:00
crontab -e
# 0 23 * * * /path/to/symphony-conductor/conductor.sh start
# 0 6  * * * /path/to/symphony-conductor/conductor.sh stop
```

## Manual usage

```bash
cd elixir
mix run --no-halt          # foreground, Ctrl-C to stop
mix test                   # run tests
mix workspace.before_remove # cleanup hook (called automatically)
```

## Security model

Three layers, outermost first:

1. **PR gate** -- nothing lands without human review. The agent opens PRs; a human merges.
2. **Worktree isolation** -- each issue gets its own shallow clone. Agents cannot access other worktrees or the host repo.
3. **Auto mode** -- Claude Code runs with `--permission-mode auto`, meaning it will execute tool calls without confirmation. This is appropriate for trusted codebases in isolated environments.

This is designed for internal/personal use on trusted repos. Do not point it at untrusted issue trackers.

## Project structure

```
conductor.sh          # start/stop wrapper with caffeinate
elixir/               # Elixir application
  WORKFLOW.md         # prompt template + config (the interesting file)
  lib/                # application source
  config/             # Elixir config
  test/               # tests
SPEC.md               # upstream Symphony specification
LICENSE               # Apache 2.0 (from upstream)
NOTICE                # OpenAI copyright notice
```

## Attribution

This is a derivative work of [OpenAI Symphony](https://github.com/openai/symphony), licensed under the Apache License 2.0. The original LICENSE and NOTICE files are preserved. See [SPEC.md](SPEC.md) for the upstream specification this implementation follows.
