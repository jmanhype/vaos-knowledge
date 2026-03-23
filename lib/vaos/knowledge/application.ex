defmodule Vaos.Knowledge.Application do
  @moduledoc "Application supervisor starting Registry and DynamicSupervisor."

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Vaos.Knowledge.Registry,
      {DynamicSupervisor, strategy: :one_for_one, name: Vaos.Knowledge.StoreSupervisor}
    ]

    opts = [strategy: :one_for_one, name: Vaos.Knowledge.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
