defmodule LoggerLogstashBackend.Socket do
  @moduledoc """
  Hides differences between `:udp` and `:tcp` sockets, so that protocol can be chosen in configuration
  """

  # Types

  @type protocol :: :tcp | :udp

  # Functions

  @doc """
  Closes the `protocol` `socket`
  """
  @spec close(map) :: :ok

  def close(%{socket: socket}), do: :inet.close(socket)

  @doc """
  Opens a `protocol` socket using [`:gen_tcp.connect/3`](http://erlang.org/doc/man/gen_tcp.html#connect-3) or
  [`:gen_udp.open/1`](http://erlang.org/doc/man/gen_udp.html#open-1).
  """
  @spec open(map) :: {:ok, map} | {:error, :inet.posix}

  def open(map = %{host: host, port: port, protocol: :tcp}) do
    host
    |> :gen_tcp.connect(port, [{:active, true}, :binary, {:keepalive, true}])
    |> put_socket(map)
  end

  def open(map = %{protocol: :udp}) do
    0
    |> :gen_udp.open
    |> put_socket(map)
  end

  @doc """
  Sends a `protocol` message over `socket`.
  """
  @spec send(map, iodata) :: :ok | {:error, :closed | :not_owner | :inet.posix}
  def send(%{protocol: :tcp, socket: socket}, packet), do: :gen_tcp.send(socket, packet)
  def send(%{host: host, port: port, protocol: :udp, socket: socket}, packet) do
    :gen_udp.send(socket, host, port, packet)
  end

  ## Private Functions

  defp put_socket({:ok, socket}, map), do: {:ok, Map.put(map, :socket, socket)}
  defp put_socket(other, _), do: other
end
