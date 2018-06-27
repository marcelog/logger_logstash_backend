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
defmodule LoggerLogstashBackend do
  @behaviour :gen_event

  def init({__MODULE__, name}) do
    {:ok, configure(name, [])}
  end

  def handle_call({:configure, opts}, %{name: name}) do
    {:ok, :ok, configure(name, opts)}
  end

  def handle_info(_, state) do
    {:ok, state}
  end

  def handle_event(:flush, state) do
    {:ok, state}
  end

  def handle_event(
        {level, _gl, {Logger, msg, ts, md}},
        %{level: min_level} = state
      ) do
    if is_nil(min_level) or Logger.compare_levels(level, min_level) != :lt do
      log_event(level, msg, ts, md, state)
    end

    {:ok, state}
  end

  def code_change(_old_vsn, state, _extra) do
    {:ok, state}
  end

  def terminate(_reason, _state) do
    :ok
  end

  defp log_event(
         level,
         msg,
         ts,
         md,
         %{type: type, metadata: metadata, timezone: timezone, json_encoder: json_encoder} = state
       ) do
    fields =
      md
      |> Keyword.merge(metadata)
      |> Enum.into(%{})
      |> Map.put(:level, to_string(level))
      |> inspect_pids

    {{year, month, day}, {hour, minute, second, microseconds}} = ts

    {:ok, ts} =
      NaiveDateTime.new(
        year,
        month,
        day,
        hour,
        minute,
        second,
        microseconds * 1000
      )

    {:ok, datetime} = DateTime.from_naive(ts, timezone)

    message =
      Map.merge(
        %{
          type: type,
          "@timestamp": DateTime.to_iso8601(datetime),
          message: to_string(msg)
        },
        fields
      )

    {:ok, json} = json_encoder.encode(message)

    send_log(state, json)
  end

  defp send_log(%{protocol: :udp, socket: socket, host: host, port: port}, json) do
    :ok = :gen_udp.send(socket, host, port, [json, "\n"])
  end

  defp send_log(%{protocol: :tcp, ssl: true, socket: socket}, json) do
    :ok = :ssl.send(socket, [json, "\n"])
  end

  defp send_log(%{protocol: :tcp, socket: socket}, json) do
    :ok = :gen_tcp.send(socket, [json, "\n"])
  end

  defp configure(name, opts) do
    env = Application.get_env(:logger, name, [])
    opts = Keyword.merge(env, opts)
    Application.put_env(:logger, name, opts)

    level = Keyword.get(opts, :level, :debug)
    metadata = Keyword.get(opts, :metadata, [])
    type = Keyword.get(opts, :type, "elixir")
    host = Keyword.get(opts, :host)
    port = Keyword.get(opts, :port)
    timezone = Keyword.get(opts, :timezone, "Etc/UTC")
    json_encoder = Keyword.get(opts, :json_encoder, Jason)
    protocol = Keyword.get(opts, :protocol, :udp)
    ssl = Keyword.get(opts, :ssl, false)

    if ssl && protocol == :udp do
      raise ArgumentError, message: "cannot use SSL in combination with UDP. Use TCP instead"
    end

    %{
      name: name,
      host: to_charlist(host),
      port: port,
      level: level,
      type: type,
      metadata: metadata,
      timezone: timezone,
      json_encoder: json_encoder,
      protocol: protocol,
      ssl: ssl
    }
    |> open_socket()
  end

  defp open_socket(%{protocol: :udp} = state) do
    {:ok, socket} = :gen_udp.open(0)
    Map.put(state, :socket, socket)
  end

  defp open_socket(%{protocol: :tcp, ssl: true} = state) do
    {:ok, socket} =
      :gen_tcp.connect(state.host, state.port, [{:active, true}, :binary, {:keepalive, true}])

    {:ok, socket} = :ssl.connect(socket, fail_if_no_peer_cert: true)
    Map.put(state, :socket, socket)
  end

  defp open_socket(%{protocol: :tcp} = state) do
    {:ok, socket} =
      :gen_tcp.connect(state.host, state.port, [{:active, true}, :binary, {:keepalive, true}])

    Map.put(state, :socket, socket)
  end

  # inspects the argument only if it is a pid
  defp inspect_pid(pid) when is_pid(pid), do: inspect(pid)
  defp inspect_pid(other), do: other

  # inspects the field values only if they are pids
  defp inspect_pids(fields) when is_map(fields) do
    Enum.into(fields, %{}, fn {key, value} ->
      {key, inspect_pid(value)}
    end)
  end
end
