defmodule Vaos.Knowledge do
  @moduledoc """
  V.A.O.S. Layer 3: Triple store with SPARQL and OWL 2 RL reasoning.
  Top-level API delegating to Store.

  Triples are raw {subject, predicate, object} 3-tuples of strings. For
  struct-based access and validation at boundaries use Vaos.Knowledge.Triple.
  """

  alias Vaos.Knowledge.Store

  @doc "Open or connect to a named store."
  def open(name, opts \\ []) do
    Store.open(name, opts)
  end

  @doc """
  Assert a triple into the store. Returns :ok or {:error, :invalid_triple}
  if any component is not a non-empty binary string.
  """
  def assert(name, {s, p, o}) when is_binary(s) and is_binary(p) and is_binary(o) do
    Store.assert(name, {s, p, o})
  end

  def assert(_name, _triple), do: {:error, :invalid_triple}

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

  @doc "Return all triples in the store."
  def all_triples(name) do
    Store.all_triples(name)
  end

  @doc "Execute a SPARQL query string."
  def sparql(name, query_string) do
    Store.sparql(name, query_string)
  end

  @doc """
  Run OWL 2 RL forward-chaining materialization on the store.
  Returns {:ok, rounds} where rounds is the number of fixpoint iterations.
  Accepts opts: [max_rounds: integer] (default 100).
  """
  def materialize(name, opts \\ []) do
    Store.materialize(name, opts)
  end
end
