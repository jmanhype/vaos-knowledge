defmodule Vaos.Knowledge.Store do
  @moduledoc "GenServer that manages a named triple store."

  use GenServer

  def child_spec(opts) do
    %{
      id: {__MODULE__, Keyword.get(opts, :name, :default)},
      start: {__MODULE__, :start_link, [opts]},
      restart: :temporary
    }
  end

  alias Vaos.Knowledge.Backend.ETS
  alias Vaos.Knowledge.Reasoner
  alias Vaos.Knowledge.Sparql

  @type name :: String.t()
  @type triple :: {String.t(), String.t(), String.t()}

  # --- Client API ---

  @doc "Start a named store GenServer. Called by DynamicSupervisor via `open/2`."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    backend = Keyword.get(opts, :backend, ETS)
    GenServer.start_link(__MODULE__, {backend, opts}, name: via(name))
  end

  @doc "Open or connect to a named store. Idempotent — returns {:ok, pid} if already running."
  @spec open(name(), keyword()) :: {:ok, pid()} | {:error, term()}
  def open(name, opts \\ []) do
    case GenServer.whereis(via(name)) do
      nil ->
        opts = Keyword.put(opts, :name, name)
        case DynamicSupervisor.start_child(
               Vaos.Knowledge.StoreSupervisor,
               {__MODULE__, opts}
             ) do
          {:ok, pid} -> {:ok, pid}
          {:error, {:already_started, pid}} -> {:ok, pid}
          error -> error
        end

      pid ->
        {:ok, pid}
    end
  end

  @doc "Assert a triple. Returns :ok or {:error, :invalid_triple}."
  @spec assert(name(), triple()) :: :ok | {:error, :invalid_triple}
  def assert(name, {s, p, o})
      when is_binary(s) and s != "" and is_binary(p) and p != "" and is_binary(o) and o != "" do
    GenServer.call(via(name), {:assert, {s, p, o}})
  end

  def assert(_name, _triple), do: {:error, :invalid_triple}

  @doc "Assert multiple triples. Silently skips invalid triples."
  @spec assert_many(name(), [triple()]) :: :ok
  def assert_many(name, triples), do: GenServer.call(via(name), {:assert_many, triples})

  @doc "Retract a triple. No-op if not present."
  @spec retract(name(), triple()) :: :ok
  def retract(name, {s, p, o}), do: GenServer.call(via(name), {:retract, {s, p, o}})

  @doc "Query triples by pattern keyword list (subject:, predicate:, object:)."
  @spec query(name(), keyword()) :: {:ok, [triple()]}
  def query(name, pattern), do: GenServer.call(via(name), {:query, pattern})

  @doc "Count triples in the store."
  @spec count(name()) :: {:ok, non_neg_integer()}
  def count(name), do: GenServer.call(via(name), :count)

  @doc "Return all triples."
  @spec all_triples(name()) :: {:ok, [triple()]}
  def all_triples(name), do: GenServer.call(via(name), :all_triples)

  @doc "Execute a SPARQL query string."
  @spec sparql(name(), String.t()) :: {:ok, term()} | {:error, term()}
  def sparql(name, query_string) when is_binary(query_string) do
    GenServer.call(via(name), {:sparql, query_string})
  end

  def sparql(_name, _query), do: {:error, :invalid_query}

  @doc "Run OWL 2 RL forward-chaining materialization through the store GenServer."
  @spec materialize(name(), keyword()) :: {:ok, non_neg_integer()}
  def materialize(name, opts \\ []) do
    GenServer.call(via(name), {:materialize, opts})
  end

  defp via(name), do: {:via, Registry, {Vaos.Knowledge.Registry, name}}

  # --- Server Callbacks ---

  @impl true
  def init({backend, opts}) do
    {:ok, backend_state} = backend.init(opts)
    {:ok, %{backend: backend, state: backend_state}}
  end

  @impl true
  def handle_call({:assert, triple}, _from, data) do
    case data.backend.assert(data.state, triple) do
      {:ok, new_state} -> {:reply, :ok, %{data | state: new_state}}
      {:error, reason} -> {:reply, {:error, reason}, data}
    end
  end

  @impl true
  def handle_call({:assert_many, triples}, _from, data) do
    {:ok, new_state} = data.backend.assert_many(data.state, triples)
    {:reply, :ok, %{data | state: new_state}}
  end

  @impl true
  def handle_call({:retract, triple}, _from, data) do
    {:ok, new_state} = data.backend.retract(data.state, triple)
    {:reply, :ok, %{data | state: new_state}}
  end

  @impl true
  def handle_call({:query, pattern}, _from, data) do
    {:ok, results} = data.backend.query(data.state, pattern)
    {:reply, {:ok, results}, data}
  end

  @impl true
  def handle_call(:count, _from, data) do
    {:ok, n} = data.backend.count(data.state)
    {:reply, {:ok, n}, data}
  end

  @impl true
  def handle_call(:all_triples, _from, data) do
    {:ok, triples} = data.backend.all_triples(data.state)
    {:reply, {:ok, triples}, data}
  end

  @impl true
  def handle_call({:sparql, query_string}, _from, data) do
    case Sparql.Parser.parse(query_string) do
      {:ok, parsed} ->
        {result, new_state} = Sparql.Executor.execute(parsed, data.backend, data.state)
        {:reply, result, %{data | state: new_state}}

      {:error, reason} ->
        {:reply, {:error, reason}, data}
    end
  end

  @impl true
  def handle_call({:materialize, opts}, _from, data) do
    case Reasoner.materialize(data.backend, data.state, opts) do
      {:ok, new_state, rounds} ->
        {:reply, {:ok, rounds}, %{data | state: new_state}}

      error ->
        {:reply, error, data}
    end
  end

  @impl true
  def handle_call(msg, _from, data) do
    {:reply, {:error, {:unknown_call, msg}}, data}
  end

  @impl true
  def terminate(_reason, data) do
    if function_exported?(data.backend, :cleanup, 1) do
      data.backend.cleanup(data.state)
    end

    :ok
  end
end
