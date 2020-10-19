defmodule Alchemy.EventStage.StageSupervisor do
  @moduledoc false
  use Supervisor
  alias Alchemy.Cogs.{CommandHandler, EventHandler, EventRegistry}

  alias Alchemy.EventStage.{
    Cacher,
    EventBuffer,
    EventDispatcher,
    CommandStage,
    EventStage,
    Tasker
  }

  def start_link(command_options) do
    Supervisor.start_link(__MODULE__, command_options, name: __MODULE__)
  end

  @limit System.schedulers_online()

  def init(command_options) do
    cogs = [
      {CommandHandler, [command_options]},
      EventHandler,
      EventRegistry
    ]

    stage1 = [EventBuffer]

    stage2 =
      for x <- 1..@limit do
        {Cacher, [x], id: x}
      end

    stage3_4 = [
      {EventDispatcher, [@limit]},
      {CommandStage, [@limit]},
      {EventStage, [@limit]},
      Tasker
    ]

    children = cogs ++ stage1 ++ stage2 ++ stage3_4

    opts = [strategy: :one_for_one]
    Supervisor.init(children, opts)
  end
end
