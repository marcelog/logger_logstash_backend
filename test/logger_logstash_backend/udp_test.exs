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
defmodule LoggerLogstashBackend.UDPTest do
  use ExUnit.Case, async: false
  require Logger
  use Timex

  @backend {LoggerLogstashBackend, :udp_test}

  setup do
    Logger.add_backend @backend
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
      Logger.remove_backend @backend
      :ok = :gen_udp.close socket
    end

    :ok
  end

  test "can log" do
    Logger.info "hello world", [key1: "field1"]

    assert {:ok, data} = JSX.decode get_log
    assert data["type"] === "some_app"
    assert data["message"] === "hello world"

    fields = data["fields"]

    assert fields["function"] == "test can log/1"
    assert fields["key1"] == "field1"
    assert fields["level"] == "info"
    assert fields["line"] == 45
    assert fields["module"] == to_string(__MODULE__)
    assert fields["pid"] == inspect(self)
    assert fields["some_metadata"] == "go here"

    {:ok, ts} = Timex.parse data["@timestamp"], "%FT%T%z", :strftime
    ts = Timex.to_unix ts

    now = Timex.to_unix Timex.DateTime.local
    assert (now - ts) < 1000
  end

  test "can log pids" do
    Logger.info "pid", [pid_key: self]

    {:ok, data} = JSX.decode get_log
    assert data["type"] === "some_app"
    assert data["message"] === "pid"

    fields = data["fields"]

    assert fields["function"] == "test can log pids/1"
    assert fields["pid_key"] == inspect(self)
    assert fields["level"] == "info"
    assert fields["line"] == 69
    assert fields["module"] == to_string(__MODULE__)
    assert fields["pid"] == inspect(self)
    assert fields["some_metadata"] == "go here"

    {:ok, ts} = Timex.parse data["@timestamp"], "%FT%T%z", :strftime
    ts = Timex.to_unix ts

    now = Timex.to_unix Timex.DateTime.local
    assert (now - ts) < 1000
  end

  test "cant log when minor levels" do
    Logger.debug "hello world", [key1: "field1"]
    :nothing_received = get_log
  end

  defp get_log do
    receive do
      {:udp, _socket, _from_ip, _from_port, json} -> json
    after 500 -> :nothing_received
    end
  end
end
