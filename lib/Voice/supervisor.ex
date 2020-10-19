defmodule Alchemy.Voice.Supervisor do
  @moduledoc false
  # Supervises the voice section, including a registry and the dynamic
  # voice client supervisor.
  use Supervisor
  alias Alchemy.Discord.Gateway.RateLimiter
  alias Alchemy.Voice.Supervisor.Gateway
  require Logger

  alias __MODULE__.Server

  def start_link do
    Supervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  defmodule Gateway do
    @moduledoc false
    use Supervisor

    def start_link(_start_arg) do
      Supervisor.start_link(__MODULE__, :ok, name: Gateway)
    end

    def child_spec(opts) do
      %{
        id: __MODULE__,
        start: {__MODULE__, :start_link, [opts]},
        type: :worker,
        restart: :permanent,
        shutdown: 500
      }
    end

    def init(_init_arg) do
      children = [
        Alchemy.Voice.Gateway
      ]

      opts = [strategy: :one_for_one]
      Supervisor.init(children, opts)
    end
  end

  def init(_init_arg) do
    children = [
      {Registry, [keys: :unique, name: Registry.Voice]},
      Alchemy.Voice.Supervisor.Gateway,
      __MODULE__.Server
    ]

    opts = [strategy: :one_for_one]
    Supervisor.init(children, opts)
  end

  defmodule VoiceRegistry do
    @moduledoc false
    def via(key) do
      {:via, Registry, {Registry.Voice, key}}
    end
  end

  defmodule Server do
    @moduledoc false
    use GenServer

    def init(init_arg) do
      {:ok, init_arg}
    end

    def start_link do
      GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
    end

    def send_to(guild, data) do
      GenServer.cast(__MODULE__, {:send_to, guild, data})
    end

    def handle_call({:start_client, guild}, {pid, _}, state) do
      case Map.get(state, guild) do
        nil ->
          {:reply, :ok, Map.put(state, guild, pid)}

        _ ->
          {:reply, {:error, "Already joining this guild"}, state}
      end
    end

    def handle_call({:client_done, guild}, _, state) do
      {:reply, :ok, Map.delete(state, guild)}
    end

    def handle_cast({:send_to, guild, data}, state) do
      case Map.get(state, guild) do
        nil -> nil
        pid -> send(pid, data)
      end

      {:noreply, state}
    end
  end

  def start_client(guild, channel, timeout) do
    r =
      with :ok <- GenServer.call(Server, {:start_client, guild}),
           [] <- Registry.lookup(Registry.Voice, {guild, :gateway}) do
        RateLimiter.change_voice_state(guild, channel)

        recv = fn ->
          receive do
            x -> {:ok, x}
          after
            div(timeout, 2) -> {:error, "Timed out"}
          end
        end

        with {:ok, {user_id, session}} <- recv.(),
             {:ok, {token, url}} <- recv.(),
             {:ok, _pid1} <-
               Supervisor.start_child(
                 Gateway,
                 [url, token, session, user_id, guild, channel]
               ),
             {:ok, _pid2} <- recv.() do
          :ok
        end
      else
        [{_pid, _} | _] ->
          RateLimiter.change_voice_state(guild, channel)
          :ok
      end

    GenServer.call(Server, {:client_done, guild})
    r
  end
end
