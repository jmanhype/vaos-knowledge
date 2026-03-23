defmodule Vaos.Knowledge do
  @moduledoc """
  V.A.O.S. Layer 3: Triple store with SPARQL and OWL 2 RL reasoning.
  Top-level API delegating to Store.

  Triples are raw {subject, predicate, object} 3-tuples of strings. For
  struct-based access and validation at boundaries use Vaos.Knowledge.Triple.

  ## Usage

      {:ok, _pid} = Vaos.Knowledge.open("my_store")
      store = Vaos.Knowledge.store_ref("my_store")
      :ok = Vaos.Knowledge.assert(store, {"alice", "knows", "bob"})
      {:ok, results} = Vaos.Knowledge.sparql(store, "SELECT ?x WHERE { ?x <knows> <bob> }")
  """

  alias Vaos.Knowledge.Store

  @type name :: String.t()
  @type triple :: {String.t(), String.t(), String.t()}
  @type pattern :: keyword()

  @doc "Open or connect to a named store. Returns {:ok, pid}."
  @spec open(name(), keyword()) :: {:ok, pid()} | {:error, term()}
  def open(name, opts \\ []) do
    Store.open(name, opts)
  end

  @doc "Close (stop) a named store. Returns :ok or {:error, :not_found}."
  @spec close(name()) :: :ok | {:error, :not_found}
  def close(name) do
    case Registry.lookup(Vaos.Knowledge.Registry, name) do
      [{pid, _}] -> DynamicSupervisor.terminate_child(Vaos.Knowledge.StoreSupervisor, pid)
      [] -> {:error, :not_found}
    end
  end

  @doc """
  Return the store name for use with all other API functions.
  Useful when you want a named reference rather than using the raw string.
  The store must already be open (see `open/2`).
  """
  @spec store_ref(name()) :: name() | {:error, :store_not_found}
  def store_ref(name) do
    case Registry.lookup(Vaos.Knowledge.Registry, name) do
      [{_pid, _}] -> name
      [] -> {:error, :store_not_found}
    end
  end

  @doc """
  Assert a triple into the store. Returns :ok or {:error, :invalid_triple}
  if any component is not a non-empty binary string.
  """
  @spec assert(name(), triple()) :: :ok | {:error, :invalid_triple}
  def assert(name, {s, p, o})
      when is_binary(s) and s != "" and is_binary(p) and p != "" and is_binary(o) and o != "" do
    Store.assert(name, {s, p, o})
  end

  def assert(_name, _triple), do: {:error, :invalid_triple}

  @doc "Assert multiple triples. Skips any triple that is not {binary, binary, binary}."
  @spec assert_many(name(), [triple()]) :: :ok
  def assert_many(name, triples) do
    Store.assert_many(name, triples)
  end

  @doc "Retract a triple from the store. No-op if the triple does not exist."
  @spec retract(name(), triple()) :: :ok
  def retract(name, {s, p, o}) do
    Store.retract(name, {s, p, o})
  end

  @doc """
  Query triples by pattern. Accepts keyword options: subject, predicate, object.
  Unspecified components are wildcards. Returns {:ok, [triple()]}.
  """
  @spec query(name(), pattern()) :: {:ok, [triple()]}
  def query(name, pattern \\ []) do
    Store.query(name, pattern)
  end

  @doc "Count triples in the store. Returns {:ok, non_neg_integer()}."
  @spec count(name()) :: {:ok, non_neg_integer()}
  def count(name) do
    Store.count(name)
  end

  @doc "Return all triples in the store as {:ok, [triple()]}."
  @spec all_triples(name()) :: {:ok, [triple()]}
  def all_triples(name) do
    Store.all_triples(name)
  end

  @doc """
  Execute a SPARQL query string. Supports SELECT, INSERT DATA, DELETE DATA.
  Returns {:ok, results} or {:error, reason}.
  """
  @spec sparql(name(), String.t()) :: {:ok, term()} | {:error, term()}
  def sparql(name, query_string) when is_binary(query_string) do
    Store.sparql(name, query_string)
  end

  def sparql(_name, _query), do: {:error, :invalid_query}

  @doc """
  Run OWL 2 RL forward-chaining materialization on the store.
  Returns {:ok, rounds} where rounds is the number of fixpoint iterations.
  Accepts opts: [max_rounds: integer] (default 100).
  """
  @spec materialize(name(), keyword()) :: {:ok, non_neg_integer()}
  def materialize(name, opts \\ []) do
    Store.materialize(name, opts)
  end
end
