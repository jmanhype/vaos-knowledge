defmodule Vaos.Knowledge.Backend.Behaviour do
  @moduledoc "Behaviour for knowledge store backends."

  @type state :: term()
  @type triple :: {String.t(), String.t(), String.t()}
  @type pattern :: keyword()

  @callback init(opts :: keyword()) :: {:ok, state()}
  @callback assert(state(), triple()) :: {:ok, state()}
  @callback assert_many(state(), [triple()]) :: {:ok, state()}
  @callback retract(state(), triple()) :: {:ok, state()}
  @callback query(state(), pattern()) :: {:ok, [triple()]}
  @callback query(state(), pattern(), keyword()) :: {:ok, [triple()]}
  @callback count(state()) :: {:ok, non_neg_integer()}
  @callback all_triples(state()) :: {:ok, [triple()]}
end
