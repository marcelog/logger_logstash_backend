defmodule LoggerLogstashBackendTest do
  use ExUnit.Case, async: false
  require Logger
  use Timex

  @backend {LoggerLogstashBackend, :test}
  Logger.add_backend @backend

  setup do
    Logger.configure_backend @backend, [
      host: "127.0.0.1",
      port: 10001,
      level: :info,
      type: "some_app",
      metadata: [
        some_metadata: "go here"
      ]
    ]
    {:ok, socket} = :gen_udp.open 10001, [:binary, {:active, true}]
    on_exit fn ->
      :ok = :gen_udp.close socket
    end
    :ok
  end

  test "can log" do
    Logger.info "hello world", [key1: "field1"]
    json = get_log
    {:ok, data} = JSX.decode json
    me = inspect self
    assert data["type"] === "some_app"
    assert data["message"] === "hello world"
    assert data["fields"] === %{
      "function" => "test can log/1",
      "level" => "info",
      "module" => "Elixir.LoggerLogstashBackendTest",
      "pid" => me,
      "some_metadata" => "go here",
      "line" => 27,
      "key1" => "field1"
    }
    {:ok, ts} = DateFormat.parse data["@timestamp"], "%FT%T%z", :strftime
    ts = Date.convert ts, :secs

    now = Date.convert Date.local, :secs

    assert (now - ts) < 1000
  end

  test "cant log when minor levels" do
    Logger.debug "hello world", [key1: "field1"]
    :nothing_received = get_log
  end

  defp get_log do
    receive do
      {:udp, _, _, _, json} -> json
    after 500 -> :nothing_received
    end
  end
end
