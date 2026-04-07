defmodule SymphonyElixir.Claude.CLI do
  @moduledoc """
  Manages Claude Code CLI subprocess sessions.

  Spawns `claude` as an Elixir Port with `--output-format stream-json`,
  parses output line by line, and reports events via callback.

  Replaces the legacy AppServer JSON-RPC protocol with direct CLI invocation.
  """

  require Logger

  alias SymphonyElixir.Claude.OutputParser

  @type session_result :: %{
          session_id: String.t(),
          exit_code: integer(),
          cost_usd: float() | nil,
          duration_ms: integer() | nil,
          turns_used: integer() | nil
        }

  @doc """
  Runs a new Claude Code session synchronously. Blocks until the CLI process exits.
  """
  @spec run(map()) :: {:ok, session_result()} | {:error, term()}
  def run(opts) do
    command = Map.get(opts, :command, "claude")
    args = build_args(opts)
    cwd = Map.fetch!(opts, :cwd)
    on_event = Map.get(opts, :on_event, fn _ -> :ok end)
    env = Map.get(opts, :env, [])
    timeout = Map.get(opts, :timeout_ms, 3_600_000)

    Logger.info("Starting Claude session #{opts.session_id} in #{cwd}")
    Logger.debug("Claude CLI args: #{inspect(args)}")

    case System.find_executable(command) do
      nil ->
        {:error, {:executable_not_found, command}}

      executable ->
        port =
          Port.open({:spawn_executable, executable}, [
            :binary,
            :exit_status,
            :use_stdio,
            :stderr_to_stdout,
            {:args, args},
            {:cd, cwd},
            {:env, Enum.map(env, fn {k, v} -> {String.to_charlist(k), String.to_charlist(v)} end)},
            {:line, 1_048_576}
          ])

        collect_output(port, opts.session_id, on_event, "", timeout)
    end
  end

  @doc """
  Resumes an existing Claude Code session. Blocks until the CLI process exits.
  """
  @spec resume(map()) :: {:ok, session_result()} | {:error, term()}
  def resume(opts) do
    command = Map.get(opts, :command, "claude")
    args = build_resume_args(opts)
    cwd = Map.fetch!(opts, :cwd)
    on_event = Map.get(opts, :on_event, fn _ -> :ok end)
    env = Map.get(opts, :env, [])
    timeout = Map.get(opts, :timeout_ms, 3_600_000)

    Logger.info("Resuming Claude session #{opts.session_id} in #{cwd}")

    case System.find_executable(command) do
      nil ->
        {:error, {:executable_not_found, command}}

      executable ->
        port =
          Port.open({:spawn_executable, executable}, [
            :binary,
            :exit_status,
            :use_stdio,
            :stderr_to_stdout,
            {:args, args},
            {:cd, cwd},
            {:env, Enum.map(env, fn {k, v} -> {String.to_charlist(k), String.to_charlist(v)} end)},
            {:line, 1_048_576}
          ])

        collect_output(port, opts.session_id, on_event, "", timeout)
    end
  end

  @doc """
  Cancels a running session by closing its port.
  """
  @spec cancel(port()) :: :ok
  def cancel(port) when is_port(port) do
    Port.close(port)
    :ok
  end

  @doc """
  Builds CLI arguments for a new session.
  """
  @spec build_args(map()) :: [String.t()]
  def build_args(opts) do
    args = [
      "-p", Map.fetch!(opts, :prompt),
      "--output-format", "stream-json",
      "--session-id", Map.fetch!(opts, :session_id),
      "--model", Map.fetch!(opts, :model),
      "--permission-mode", Map.fetch!(opts, :permission_mode)
    ]

    args = maybe_add_allowed_tools(args, Map.get(opts, :allowed_tools, []))
    args = maybe_add_flag(args, "--max-turns", Map.get(opts, :max_turns))
    args = maybe_add_float_flag(args, "--max-budget-usd", Map.get(opts, :max_budget_usd))
    args
  end

  @doc """
  Builds CLI arguments for resuming a session.
  """
  @spec build_resume_args(map()) :: [String.t()]
  def build_resume_args(opts) do
    [
      "--resume", Map.fetch!(opts, :session_id),
      "-p", Map.fetch!(opts, :prompt),
      "--output-format", "stream-json"
    ]
  end

  @doc """
  Generates a deterministic session ID from an issue identifier and turn number.
  """
  @spec session_id(String.t(), integer()) :: String.t()
  def session_id(identifier, turn) do
    "symphony-#{identifier}-turn-#{turn}"
  end

  # --- Private ---

  defp collect_output(port, session_id, on_event, buffer, timeout) do
    receive do
      {^port, {:data, {:eol, line}}} ->
        full_line = buffer <> line
        event = OutputParser.parse_line(full_line)
        on_event.(event)

        case event do
          {:result, result} ->
            collect_exit(port, %{
              session_id: result["session_id"] || session_id,
              cost_usd: result["cost_usd"],
              duration_ms: result["duration_ms"],
              turns_used: result["turns_used"]
            })

          {:error, message} ->
            Logger.warning("Claude session #{session_id} error: #{message}")
            collect_output(port, session_id, on_event, "", timeout)

          _ ->
            collect_output(port, session_id, on_event, "", timeout)
        end

      {^port, {:data, {:noeol, chunk}}} ->
        collect_output(port, session_id, on_event, buffer <> chunk, timeout)

      {^port, {:exit_status, code}} ->
        if code == 0 do
          {:ok, %{session_id: session_id, exit_code: code, cost_usd: nil, duration_ms: nil, turns_used: nil}}
        else
          {:error, {:exit_code, code}}
        end
    after
      timeout ->
        Port.close(port)
        {:error, :timeout}
    end
  end

  defp collect_exit(port, result) do
    receive do
      {^port, {:exit_status, code}} ->
        if code == 0 do
          {:ok, Map.put(result, :exit_code, code)}
        else
          {:error, {:exit_code, code, result}}
        end

      {^port, {:data, _}} ->
        collect_exit(port, result)
    after
      30_000 ->
        Port.close(port)
        {:ok, Map.put(result, :exit_code, 0)}
    end
  end

  defp maybe_add_allowed_tools(args, []), do: args
  defp maybe_add_allowed_tools(args, tools), do: args ++ ["--allowedTools", Enum.join(tools, ",")]

  defp maybe_add_flag(args, _flag, nil), do: args
  defp maybe_add_flag(args, flag, value), do: args ++ [flag, to_string(value)]

  defp maybe_add_float_flag(args, _flag, nil), do: args

  defp maybe_add_float_flag(args, flag, value) when is_float(value),
    do: args ++ [flag, :erlang.float_to_binary(value, decimals: 1)]

  defp maybe_add_float_flag(args, flag, value), do: args ++ [flag, to_string(value)]
end
