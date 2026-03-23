defmodule Vaos.Knowledge.Backend.ETS do
  @moduledoc """
  ETS-backed triple store with 3-way indexing (SPO, POS, OSP).
  Provides O(1) lookup on any triple component.
  """

  @behaviour Vaos.Knowledge.Backend.Behaviour

  defstruct [:spo, :pos, :osp]

  @type state :: %__MODULE__{spo: :ets.tid(), pos: :ets.tid(), osp: :ets.tid()}

  @impl true
  @spec init(keyword()) :: {:ok, state()}
  def init(opts) do
    name = Keyword.get(opts, :name, :default)
    ts = System.unique_integer([:positive])
    spo = :ets.new(:"#{name}_spo_#{ts}", [:set, :public])
    pos = :ets.new(:"#{name}_pos_#{ts}", [:set, :public])
    osp = :ets.new(:"#{name}_osp_#{ts}", [:set, :public])
    {:ok, %__MODULE__{spo: spo, pos: pos, osp: osp}}
  end

  @impl true
  @spec assert(state(), Vaos.Knowledge.Backend.Behaviour.triple()) ::
          {:ok, state()} | {:error, :invalid_triple}
  def assert(state, {s, p, o}) when is_binary(s) and is_binary(p) and is_binary(o) do
    :ets.insert(state.spo, {{s, p, o}})
    :ets.insert(state.pos, {{p, o, s}})
    :ets.insert(state.osp, {{o, s, p}})
    {:ok, state}
  end

  def assert(_state, {_s, _p, _o}), do: {:error, :invalid_triple}

  @impl true
  @spec assert_many(state(), [Vaos.Knowledge.Backend.Behaviour.triple()]) :: {:ok, state()}
  def assert_many(state, triples) when is_list(triples) do
    Enum.each(triples, fn triple ->
      case triple do
        {s, p, o} when is_binary(s) and is_binary(p) and is_binary(o) ->
          :ets.insert(state.spo, {{s, p, o}})
          :ets.insert(state.pos, {{p, o, s}})
          :ets.insert(state.osp, {{o, s, p}})

        _invalid ->
          :skip
      end
    end)
    {:ok, state}
  end

  @impl true
  @spec retract(state(), Vaos.Knowledge.Backend.Behaviour.triple()) :: {:ok, state()}
  def retract(state, {s, p, o}) do
    :ets.delete(state.spo, {s, p, o})
    :ets.delete(state.pos, {p, o, s})
    :ets.delete(state.osp, {o, s, p})
    {:ok, state}
  end

  @impl true
  @spec query(state(), keyword()) :: {:ok, [Vaos.Knowledge.Backend.Behaviour.triple()]}
  def query(state, pattern) do
    s = Keyword.get(pattern, :subject)
    p = Keyword.get(pattern, :predicate)
    o = Keyword.get(pattern, :object)

    results = do_query(state, s, p, o)
    {:ok, results}
  end

  @impl true
  @spec count(state()) :: {:ok, non_neg_integer()}
  def count(state) do
    {:ok, :ets.info(state.spo, :size)}
  end

  @impl true
  @spec all_triples(state()) :: {:ok, [Vaos.Knowledge.Backend.Behaviour.triple()]}
  def all_triples(state) do
    triples =
      :ets.tab2list(state.spo)
      |> Enum.map(fn {{s, p, o}} -> {s, p, o} end)
    {:ok, triples}
  end

  # All three specified — direct lookup
  defp do_query(state, s, p, o) when not is_nil(s) and not is_nil(p) and not is_nil(o) do
    case :ets.lookup(state.spo, {s, p, o}) do
      [_] -> [{s, p, o}]
      [] -> []
    end
  end

  # Subject specified — scan SPO table
  defp do_query(state, s, nil, nil) when not is_nil(s) do
    :ets.tab2list(state.spo)
    |> Enum.filter(fn {{subj, _p, _o}} -> subj == s end)
    |> Enum.map(fn {{subj, pred, obj}} -> {subj, pred, obj} end)
  end

  # Predicate specified — scan POS table
  defp do_query(state, nil, p, nil) when not is_nil(p) do
    :ets.tab2list(state.pos)
    |> Enum.filter(fn {{pred, _o, _s}} -> pred == p end)
    |> Enum.map(fn {{pred, obj, subj}} -> {subj, pred, obj} end)
  end

  # Object specified — scan OSP table
  defp do_query(state, nil, nil, o) when not is_nil(o) do
    :ets.tab2list(state.osp)
    |> Enum.filter(fn {{obj, _s, _p}} -> obj == o end)
    |> Enum.map(fn {{obj, subj, pred}} -> {subj, pred, obj} end)
  end

  # Subject + Predicate — scan SPO
  defp do_query(state, s, p, nil) when not is_nil(s) and not is_nil(p) do
    :ets.tab2list(state.spo)
    |> Enum.filter(fn {{subj, pred, _o}} -> subj == s and pred == p end)
    |> Enum.map(fn {{subj, pred, obj}} -> {subj, pred, obj} end)
  end

  # Subject + Object — scan SPO
  defp do_query(state, s, nil, o) when not is_nil(s) and not is_nil(o) do
    :ets.tab2list(state.spo)
    |> Enum.filter(fn {{subj, _p, obj}} -> subj == s and obj == o end)
    |> Enum.map(fn {{subj, pred, obj}} -> {subj, pred, obj} end)
  end

  # Predicate + Object — scan POS
  defp do_query(state, nil, p, o) when not is_nil(p) and not is_nil(o) do
    :ets.tab2list(state.pos)
    |> Enum.filter(fn {{pred, obj, _s}} -> pred == p and obj == o end)
    |> Enum.map(fn {{pred, obj, subj}} -> {subj, pred, obj} end)
  end

  # No filters — return all
  defp do_query(state, nil, nil, nil) do
    :ets.tab2list(state.spo)
    |> Enum.map(fn {{s, p, o}} -> {s, p, o} end)
  end
  @doc "Explicitly delete ETS tables when the store is shutting down."
  def cleanup(state) do
    :ets.delete(state.spo)
    :ets.delete(state.pos)
    :ets.delete(state.osp)
    :ok
  end
end
