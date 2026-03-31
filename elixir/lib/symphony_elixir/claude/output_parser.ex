defmodule SymphonyElixir.Claude.OutputParser do
  @moduledoc """
  Parses stream-json output lines from the Claude Code CLI.

  Each line from `claude --output-format stream-json` is a JSON object.
  This module classifies each line into a tagged tuple for pattern matching.
  """

  @spec parse_line(String.t()) ::
          {:assistant_message, map()}
          | {:tool_use, String.t(), map()}
          | {:tool_result, String.t(), String.t()}
          | {:result, map()}
          | {:error, String.t()}
          | {:unknown, map()}
          | {:unparseable, String.t()}
  def parse_line(line) when is_binary(line) do
    case Jason.decode(line) do
      {:ok, parsed} -> classify(parsed)
      {:error, _} -> {:unparseable, line}
    end
  end

  defp classify(%{"type" => "assistant", "message" => message}), do: {:assistant_message, message}
  defp classify(%{"type" => "tool_use", "tool" => tool, "input" => input}), do: {:tool_use, tool, input}
  defp classify(%{"type" => "tool_result", "tool" => tool, "output" => output}), do: {:tool_result, tool, output}
  defp classify(%{"type" => "result"} = result), do: {:result, result}
  defp classify(%{"type" => "error", "error" => %{"message" => msg}}), do: {:error, msg}
  defp classify(%{"type" => "error", "error" => msg}) when is_binary(msg), do: {:error, msg}
  defp classify(other) when is_map(other), do: {:unknown, other}
end
