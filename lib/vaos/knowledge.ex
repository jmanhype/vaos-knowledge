defmodule Vaos.Knowledge do
  @moduledoc """
  V.A.O.S. Layer 3: Triple store with SPARQL and OWL 2 RL reasoning.
  Top-level API delegating to Store.
  """

  alias Vaos.Knowledge.Store

  @doc "Open or connect to a named store."
  def open(name, opts \\ []) do
    Store.open(name, opts)
  end

  @doc "Assert a triple into the store."
  def assert(name, {s, p, o}) do
    Store.assert(name, {s, p, o})
  end

  @doc "Assert multiple triples."
  def assert_many(name, triples) do
    Store.assert_many(name, triples)
  end

  @doc "Retract a triple from the store."
  def retract(name, {s, p, o}) do
    Store.retract(name, {s, p, o})
  end

  @doc "Query triples by pattern."
  def query(name, pattern \\ []) do
    Store.query(name, pattern)
  end

  @doc "Count triples in the store."
  def count(name) do
    Store.count(name)
  end

  @doc "Execute a SPARQL query string."
  def sparql(name, query_string) do
    Store.sparql(name, query_string)
  end
end
