defmodule SymphonyElixir.Claude.OutputParserTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Claude.OutputParser

  describe "parse_line/1" do
    test "parses assistant message" do
      line = ~s({"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Reading the file..."}]}})
      assert {:assistant_message, %{"role" => "assistant", "content" => [%{"type" => "text", "text" => "Reading the file..."}]}} = OutputParser.parse_line(line)
    end

    test "parses tool_use event" do
      line = ~s({"type":"tool_use","tool":"Read","input":{"file_path":"/tmp/test.ex"}})
      assert {:tool_use, "Read", %{"file_path" => "/tmp/test.ex"}} = OutputParser.parse_line(line)
    end

    test "parses tool_result event" do
      line = ~s({"type":"tool_result","tool":"Read","output":"file contents..."})
      assert {:tool_result, "Read", "file contents..."} = OutputParser.parse_line(line)
    end

    test "parses result event with session info" do
      line = ~s({"type":"result","session_id":"abc-123","cost_usd":0.05,"duration_ms":12000,"turns_used":3})
      assert {:result, %{"session_id" => "abc-123", "cost_usd" => 0.05, "duration_ms" => 12000, "turns_used" => 3}} = OutputParser.parse_line(line)
    end

    test "parses error event" do
      line = ~s({"type":"error","error":{"message":"Rate limited"}})
      assert {:error, "Rate limited"} = OutputParser.parse_line(line)
    end

    test "handles malformed JSON gracefully" do
      assert {:unparseable, "not json at all"} = OutputParser.parse_line("not json at all")
    end

    test "handles unknown event types" do
      line = ~s({"type":"unknown_future_type","data":"something"})
      assert {:unknown, %{"type" => "unknown_future_type", "data" => "something"}} = OutputParser.parse_line(line)
    end
  end
end
