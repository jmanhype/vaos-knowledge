defmodule Vaos.Knowledge.Registry do
  @moduledoc "Registry for named store lookup."

  def child_spec(_opts) do
    Registry.child_spec(keys: :unique, name: __MODULE__)
  end
end
