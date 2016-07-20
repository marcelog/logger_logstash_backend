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
defmodule LoggerLogstashBackend.TCPTest do
  use ExUnit.Case, async: false
  require Logger
  use Timex

  import ExUnit.CaptureIO

  # Functions

  def accept(listen_socket), do: :gen_tcp.accept(listen_socket, 1_000)

  def assert_logged_to_stderr(message) do
    assert capture_logger_info(message) =~ message
  end

  def capture_logger_info(message) do
    capture_io :stderr, fn ->
      Logger.info message
      :timer.sleep 100
    end
  end

  def capture_setup_backend(context) do
    capture_io :stderr, fn ->
      context
      |> Map.put(:backend, true)
      |> setup_backend
    end
  end

  def listen(port \\ 0) do
    :gen_tcp.listen port, [:binary, {:active, true}, {:ip, {127, 0, 0, 1}}, {:reuseaddr, true}]
  end

  def setup_accept(context = %{accept: true}) do
    %{listen_socket: listen_socket} = context

    {:ok, accept_socket} = accept(listen_socket)

    on_exit fn ->
      :ok = :gen_tcp.close accept_socket
    end

    Map.put(context, :accept_socket, accept_socket)
  end
  def setup_accept(context), do: context

  def setup_backend(context = %{backend: true}) do
    # don't include in function head so that backend true will always match even if forgot to populate :port
    %{line: line, port: port} = context

    backend = {LoggerLogstashBackend, String.to_atom("#{inspect __MODULE__}:#{line}")}

    Logger.add_backend backend
    Logger.configure_backend backend, [
      host: "127.0.0.1",
      port: port,
      level: :info,
      type: "some_app",
      metadata: [
        some_metadata: "go here"
      ],
      protocol: :tcp
    ]

    on_exit fn ->
      Logger.remove_backend backend
    end

    context
  end
  def setup_backend(context), do: context

  def setup_listen(context = %{listen: true}) do
    {:ok, listen_socket} = listen
    {:ok, port} = :inet.port(listen_socket)

    on_exit fn ->
      :ok = :gen_tcp.close listen_socket
    end

    context
    |> Map.put(:listen_socket, listen_socket)
    |> Map.put(:port, port)
  end
  def setup_listen(context), do: context

  # Callbacks

  setup context do
    full_context = context
                   # have to open socket before configure_backend, so that it is listening when connect happens
                   |> setup_listen
                   |> setup_backend
                   |> setup_accept

    {:ok, full_context}
  end

  @tag :accept
  @tag :backend
  @tag :listen
  test "can log" do
    Logger.info "hello world", [key1: "field1"]

    assert {:ok, data} = JSX.decode get_log!
    assert data["type"] === "some_app"
    assert data["message"] === "hello world"

    fields = data["fields"]

    assert fields["function"] == "test can log/1"
    assert fields["key1"] == "field1"
    assert fields["level"] == "info"
    assert fields["line"] == 119
    assert fields["module"] == to_string(__MODULE__)
    assert fields["pid"] == inspect(self)
    assert fields["some_metadata"] == "go here"

    {:ok, ts} = Timex.parse data["@timestamp"], "%FT%T%z", :strftime
    ts = Timex.to_unix ts

    now = Timex.to_unix Timex.DateTime.local
    assert (now - ts) < 1000
  end

  @tag :accept
  @tag :backend
  @tag :listen
  test "can log pids" do
    Logger.info "pid", [pid_key: self]

    {:ok, data} = JSX.decode get_log!
    assert data["type"] === "some_app"
    assert data["message"] === "pid"

    fields = data["fields"]

    assert fields["function"] == "test can log pids/1"
    assert fields["pid_key"] == inspect(self)
    assert fields["level"] == "info"
    assert fields["line"] == 146
    assert fields["module"] == to_string(__MODULE__)
    assert fields["pid"] == inspect(self)
    assert fields["some_metadata"] == "go here"

    {:ok, ts} = Timex.parse data["@timestamp"], "%FT%T%z", :strftime
    ts = Timex.to_unix ts

    now = Timex.to_unix Timex.DateTime.local
    assert (now - ts) < 1000
  end

  @tag :accept
  @tag :backend
  @tag :listen
  test "cant log when minor levels" do
    Logger.debug "hello world", [key1: "field1"]
    {:error, :nothing_received} = get_log
  end

  @tag :accept
  @tag :backend
  @tag :listen
  test "it reconnects if disconnected", %{accept_socket: accept_socket, listen_socket: listen_socket} do
    :ok = :gen_tcp.close accept_socket

    assert {:ok, _} = :gen_tcp.accept(listen_socket, 1_000)
  end

  @tag :accept
  @tag :backend
  @tag :listen
  test "it reconnects on send if disconnected and listening socket is closed " <>
       "when handle_info({:tcp_closed, _}, _) is called",
       %{accept_socket: accept_socket, listen_socket: listen_socket, port: port} do
    :ok = :gen_tcp.close listen_socket
    :ok = :gen_tcp.close accept_socket

    # suppress error messages not being tested
    capture_logger_info "Can't connect"

    {:ok, new_listen_socket} = listen(port)

    # Need to accept and wait in a separate process because connect won't come until the Logger.info call tries to
    # establish a new socket
    pid = self
    spawn_link fn ->
      {:ok, new_accept_socket} = accept(new_listen_socket)

      send pid, {:new_accept_socket, new_accept_socket}

      receive do
        # forward to pid so that get_log! works as normal
        message = {:tcp, _, _} -> send pid, message
      end
    end

    Logger.info "I reconnected"

    assert_receive {:new_accept_socket, _}

    :timer.sleep 100

    {:ok, data} = JSX.decode get_log!

    assert data["message"] == "I reconnected"
  end

  @tag :accept
  @tag :backend
  @tag :listen
  test "if it can't reconnect, then is prints to :stderr",
       %{accept_socket: accept_socket, listen_socket: listen_socket} do
    :ok = :gen_tcp.close listen_socket
    :ok = :gen_tcp.close accept_socket

    assert_logged_to_stderr("Logged to stderr")
  end

  @tag :listen
  test "if it can't connect, then it prints to :stderr", context = %{listen_socket: listen_socket, port: port} do
    :ok = :gen_tcp.close listen_socket

    assert capture_setup_backend(context) =~ "Could not open socket (tcp://127.0.0.1:#{port}) due to reason :econnrefused\n"
  end

  @tag :listen
  test "if it can't connect, then any log messages print to :stderr", context = %{listen_socket: listen_socket} do
    :ok = :gen_tcp.close listen_socket
    capture_setup_backend(context)

    assert_logged_to_stderr("Logged to stderr")
  end

  defp get_log do
    receive do
      {:tcp, _socket, json} -> {:ok, json}
    after 500 -> {:error, :nothing_received}
    end
  end

  defp get_log! do
    {:ok, log} = get_log

    log
  end
end
