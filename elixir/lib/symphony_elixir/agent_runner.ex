defmodule SymphonyElixir.AgentRunner do
  @moduledoc """
  Executes a single Linear issue in its workspace with Claude Code CLI.
  """

  require Logger
  alias SymphonyElixir.Claude.CLI, as: ClaudeCode
  alias SymphonyElixir.{Config, Linear.Issue, PromptBuilder, Tracker, Workspace}

  @type worker_host :: String.t() | nil

  @spec run(map(), pid() | nil, keyword()) :: :ok | no_return()
  def run(issue, update_recipient \\ nil, opts \\ []) do
    # The orchestrator owns host retries so one worker lifetime never hops machines.
    worker_host = selected_worker_host(Keyword.get(opts, :worker_host), Config.settings!().worker.ssh_hosts)

    Logger.info("Starting agent run for #{issue_context(issue)} worker_host=#{worker_host_for_log(worker_host)}")

    case run_on_worker_host(issue, update_recipient, opts, worker_host) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.error("Agent run failed for #{issue_context(issue)}: #{inspect(reason)}")
        raise RuntimeError, "Agent run failed for #{issue_context(issue)}: #{inspect(reason)}"
    end
  end

  defp run_on_worker_host(issue, update_recipient, opts, worker_host) do
    Logger.info("Starting worker attempt for #{issue_context(issue)} worker_host=#{worker_host_for_log(worker_host)}")

    case Workspace.create_for_issue(issue, worker_host) do
      {:ok, workspace} ->
        send_worker_runtime_info(update_recipient, issue, worker_host, workspace)

        try do
          with :ok <- Workspace.run_before_run_hook(workspace, issue, worker_host) do
            run_claude_session(workspace, issue, update_recipient, opts)
          end
        after
          Workspace.run_after_run_hook(workspace, issue, worker_host)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp run_claude_session(workspace, issue, update_recipient, opts) do
    config = Config.settings!().claude
    identifier = issue.identifier
    workflow_prompt = PromptBuilder.build_prompt(issue, opts)
    linear_api_key = Config.settings!().tracker.api_key

    # Generate workspace files for Claude Code
    Workspace.generate_claude_md(workspace, issue, workflow_prompt)
    Workspace.generate_mcp_json(workspace, linear_api_key)
    Workspace.generate_claude_settings(workspace, [])

    on_event =
      if is_pid(update_recipient) do
        fn event -> send(update_recipient, {:claude_event, issue.id, event}) end
      else
        fn _event -> :ok end
      end

    issue_state_fetcher = Keyword.get(opts, :issue_state_fetcher, &Tracker.fetch_issue_states_by_ids/1)
    max_turns = Config.settings!().agent.max_turns
    do_run_turns(workspace, issue, config, on_event, issue_state_fetcher, identifier, 1, max_turns)
  end

  defp do_run_turns(_workspace, _issue, _config, _on_event, _issue_state_fetcher, _identifier, turn, max_turns)
       when turn > max_turns do
    Logger.info("Max turns (#{max_turns}) reached")
    :ok
  end

  defp do_run_turns(workspace, issue, config, on_event, issue_state_fetcher, identifier, turn, max_turns, last_session_id \\ nil) do
    result =
      if turn == 1 do
        ClaudeCode.run(%{
          command: config.command,
          prompt: "Work on this issue. Read CLAUDE.md for full context.",
          cwd: workspace,
          model: config.model,
          permission_mode: config.permission_mode,
          allowed_tools: config.allowed_tools,
          max_turns: config.max_turns,
          max_budget_usd: config.max_budget_usd,
          on_event: on_event,
          env: []
        })
      else
        fresh_issue =
          case Tracker.fetch_issue_states_by_ids([issue.id]) do
            {:ok, [refreshed | _]} -> refreshed
            _ -> issue
          end

        continuation_prompt = build_continuation_prompt(fresh_issue)

        ClaudeCode.resume(%{
          command: config.command,
          session_id: last_session_id,
          prompt: continuation_prompt,
          cwd: workspace,
          on_event: on_event,
          env: []
        })
      end

    case result do
      {:ok, session} ->
        Logger.info(
          "Claude session #{session.session_id} completed (exit #{session.exit_code}, cost $#{session.cost_usd || "?"})"
        )

        case continue_with_issue?(issue, issue_state_fetcher) do
          {:continue, _refreshed_issue} when turn < max_turns ->
            do_run_turns(workspace, issue, config, on_event, issue_state_fetcher, identifier, turn + 1, max_turns, session.session_id)

          {:continue, _refreshed_issue} ->
            Logger.info("Reached max_turns for #{issue_context(issue)} with issue still active")
            :ok

          {:done, _refreshed_issue} ->
            :ok

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        Logger.error("Claude session for #{identifier} turn #{turn} failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp build_continuation_prompt(issue) do
    """
    Continue working on this issue. The workspace has your previous work.

    Current issue state: #{issue.state}
    Latest comments or feedback may have been added — check Linear for updates.

    Review what you've done so far and continue. If you've already opened a PR, check for review feedback.
    """
  end

  defp continue_with_issue?(%Issue{id: issue_id} = issue, issue_state_fetcher) when is_binary(issue_id) do
    case issue_state_fetcher.([issue_id]) do
      {:ok, [%Issue{} = refreshed_issue | _]} ->
        if active_issue_state?(refreshed_issue.state) do
          {:continue, refreshed_issue}
        else
          {:done, refreshed_issue}
        end

      {:ok, []} ->
        {:done, issue}

      {:error, reason} ->
        {:error, {:issue_state_refresh_failed, reason}}
    end
  end

  defp continue_with_issue?(issue, _issue_state_fetcher), do: {:done, issue}

  defp active_issue_state?(state_name) when is_binary(state_name) do
    normalized_state = normalize_issue_state(state_name)

    Config.settings!().tracker.active_states
    |> Enum.any?(fn active_state -> normalize_issue_state(active_state) == normalized_state end)
  end

  defp active_issue_state?(_state_name), do: false

  defp send_worker_runtime_info(recipient, %Issue{id: issue_id}, worker_host, workspace)
       when is_binary(issue_id) and is_pid(recipient) and is_binary(workspace) do
    send(
      recipient,
      {:worker_runtime_info, issue_id,
       %{
         worker_host: worker_host,
         workspace_path: workspace
       }}
    )

    :ok
  end

  defp send_worker_runtime_info(_recipient, _issue, _worker_host, _workspace), do: :ok

  defp selected_worker_host(nil, []), do: nil

  defp selected_worker_host(preferred_host, configured_hosts) when is_list(configured_hosts) do
    hosts =
      configured_hosts
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.uniq()

    case preferred_host do
      host when is_binary(host) and host != "" -> host
      _ when hosts == [] -> nil
      _ -> List.first(hosts)
    end
  end

  defp worker_host_for_log(nil), do: "local"
  defp worker_host_for_log(worker_host), do: worker_host

  defp normalize_issue_state(state_name) when is_binary(state_name) do
    state_name
    |> String.trim()
    |> String.downcase()
  end

  defp issue_context(%Issue{id: issue_id, identifier: identifier}) do
    "issue_id=#{issue_id} issue_identifier=#{identifier}"
  end
end
