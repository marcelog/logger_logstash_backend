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
  alias LoggerLogstashBackend.Socket

  use GenEvent
  use Timex

  # Struct

  defstruct ~w(
               host
               level
               metadata
               name
               port
               protocol
               socket
               type
             )a

  # Functions

  ## GenEvent callbacks

  def init({__MODULE__, name}) do
    # trap exits, so that cleanup can occur in terminate/2
    Process.flag(:trap_exit, true)

    configure(name, [])
  end

  def handle_call({:configure, opts}, %{name: name}) do
    case configure(name, opts) do
      {:ok, state} ->
        {:ok, :ok, state}
      reply = {:error, _reason} ->
        {:remove_handler, reply}
    end
  end

  def handle_event(
    {level, _gl, {Logger, msg, ts, md}}, %{level: min_level} = state
  ) do
    if is_nil(min_level) or Logger.compare_levels(level, min_level) != :lt do
      log_event level, msg, ts, md, state
    else
      {:ok, state}
    end
  end

  def handle_info({:tcp_closed, socket}, state = %__MODULE__{host: host, port: port, socket: socket}) do
    case configure_socket(state, host, port) do
      {:error, _} -> {:ok, %{state | socket: nil}}
      other -> other
    end
  end

  def handle_info(_, state) do
    {:ok, state}
  end

  @doc """
  Closes socket when the backend is removed
  """
  def terminate(_, state)  do
    :ok = Socket.close(state)

    state
  end

  ## Private Functions

  defp log_event(
    level, msg, ts, md, state = %{
      type: type,
      metadata: metadata
    }
  ) do
    fields = md
             |> Keyword.merge(metadata)
             |> Enum.into(%{})
             |> Map.put(:level, to_string(level))
             |> inspect_pids

    ts = Timex.datetime(ts, :local)
    {:ok, json} = JSX.encode %{
      type: type,
      "@timestamp": Timex.format!(ts, "%FT%T%z", :strftime),
      message: to_string(msg),
      fields: fields
    }

    send_with_retry(state, json)
  end

  defp configure(name, opts) when is_atom(name) and is_list(opts) do
    env = Application.get_env :logger, name, []
    opts = Keyword.merge env, opts
    Application.put_env :logger, name, opts

    level = Keyword.get opts, :level, :debug
    metadata = Keyword.get opts, :metadata, []
    type = Keyword.get opts, :type, "elixir"
    host = Keyword.get opts, :host
    port = Keyword.get opts, :port
    protocol = Keyword.get opts, :protocol, :udp

    state = %__MODULE__{level: level, metadata: metadata, name: name, protocol: protocol, type: type}

    configure_socket(state, host, port)
  end

  defp configure_socket(state = %__MODULE__{host: host, port: port}) do
    case Socket.open %{state | host: to_char_list(host), port: port} do
      reply = {:error, reason} ->
        IO.puts :stderr, "Could not open socket (#{url(state)}) due to reason #{inspect reason}"

        reply
      other ->
        other
    end
  end

  defp configure_socket(state, host, port) when is_nil(host) or is_nil(port), do: {:ok, state}
  defp configure_socket(state, host, port), do: configure_socket %{state | host: to_char_list(host), port: port}

  defp fallback_log(state, json, reason) do
    IO.puts :stderr,
            "Could not log message (#{json}) to socket (#{url(state)}) due to #{inspect reason}.  " <>
            "Check that state (#{inspect state}) is correct."
  end

  # inspects the argument only if it is a pid
  defp inspect_pid(pid) when is_pid(pid), do: inspect(pid)
  defp inspect_pid(other), do: other

  # inspects the field values only if they are pids
  defp inspect_pids(fields) when is_map(fields) do
    Enum.into fields, %{}, fn {key, value} ->
      {key, inspect_pid(value)}
    end
  end

  defp send_with_retry(state = %__MODULE__{socket: nil}, json), do: send_with_new_socket(state, json)
  defp send_with_retry(state, json) do
    case Socket.send(state, [json, "\n"]) do
      :ok ->
        {:ok, state}
      {:error, :closed} ->
        send_with_new_socket(state, json)
      {:error, reason} ->
        fallback_log(state, json, reason)

        {:ok, state}
    end
  end

  defp send_with_new_socket(state, json) do
    case configure_socket(state) do
      {:error, reason} ->
        fallback_log(state, json, reason)

        {:ok, state}
      {:ok, new_state} ->
        send_with_retry(new_state, json)
    end
  end

  defp url(%__MODULE__{host: host, port: port, protocol: protocol}) do
    "#{protocol}://#{host}:#{port}"
  end
end
