################################################################################
# Copyright 2015 Marcelo Gornstein <marcelog@gmail.com>
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
################################################################################
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
    assert data["type"] === "some_app"
    assert data["message"] === "hello world"
    expected = %{
      "function" => "test can log/1",
      "level" => "info",
      "module" => "Elixir.LoggerLogstashBackendTest",
      "pid" => (inspect self),
      "some_metadata" => "go here",
      "line" => 42,
      "key1" => "field1"
    }
    assert contains?(data["fields"], expected)
    {:ok, ts} = Timex.parse data["@timestamp"], "{ISO:Extended}"
    ts = Timex.to_unix ts

    now = Timex.to_unix Timex.local
    assert (now - ts) < 1000
  end

  test "can log pids" do
    Logger.info "pid", [pid_key: self]
    json = get_log
    {:ok, data} = JSX.decode json
    assert data["type"] === "some_app"
    assert data["message"] === "pid"
    expected = %{
      "function" => "test can log pids/1",
      "level" => "info",
      "module" => "Elixir.LoggerLogstashBackendTest",
      "pid" => (inspect self),
      "pid_key" => inspect(self),
      "some_metadata" => "go here",
      "line" => 65
    }
    assert contains?(data["fields"], expected)
    {:ok, ts} = Timex.parse data["@timestamp"], "{ISO:Extended}"
    ts = Timex.to_unix ts

    now = Timex.to_unix Timex.local
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

  defp contains?(map1, map2) do
    Enum.all?(Map.to_list(map2), fn {key, value} ->
      Map.fetch!(map1, key) == value
    end)
  end
end
