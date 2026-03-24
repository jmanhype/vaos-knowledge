defmodule Vaos.Knowledge.Backend.ETS do
  @moduledoc """
  ETS-backed triple store with 3-way indexing (SPO, POS, OSP).
  Provides O(1) lookup on any triple component via :ets.match_object.
  """

  @behaviour Vaos.Knowledge.Backend.Behaviour

  @mix_env Mix.env()

  require Logger

  defstruct [:spo, :pos, :osp, :journal_path]

  @type state :: %__MODULE__{spo: :ets.tid(), pos: :ets.tid(), osp: :ets.tid()}

  @impl true
  @spec init(keyword()) :: {:ok, state()}
  def init(opts) do
    name = Keyword.get(opts, :name, :default)
    ts = System.unique_integer([:positive])
    spo = :ets.new(:"#{name}_spo_#{ts}", [:set, :protected])
    pos = :ets.new(:"#{name}_pos_#{ts}", [:set, :protected])
    osp = :ets.new(:"#{name}_osp_#{ts}", [:set, :protected])

    journal_dir = Keyword.get(opts, :journal_dir, if(@mix_env == :test, do: System.tmp_dir!() <> "/vaos_kg_test_" <> to_string(System.unique_integer([:positive])) <> "_" <> to_string(:os.system_time(:millisecond)), else: Path.join(System.user_home!(), ".vaos/knowledge")))
    File.mkdir_p!(journal_dir)
    journal_path = Path.join(journal_dir, "#{name}.jsonl")
    state = %__MODULE__{spo: spo, pos: pos, osp: osp, journal_path: journal_path}
    state = replay_journal(state)
    {:ok, state}
  end

  @impl true
  @spec assert(state(), Vaos.Knowledge.Backend.Behaviour.triple()) ::
          {:ok, state()} | {:error, :invalid_triple}
  def assert(state, {s, p, o}) when is_binary(s) and is_binary(p) and is_binary(o) do
    :ets.insert(state.spo, {{s, p, o}})
    :ets.insert(state.pos, {{p, o, s}})
    :ets.insert(state.osp, {{o, s, p}})
    journal_write(state, "assert", {s, p, o})
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
          journal_write(state, "assert", {s, p, o})

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
    journal_write(state, "retract", {s, p, o})
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

  # Subject specified — prefix match on SPO index
  defp do_query(state, s, nil, nil) when not is_nil(s) do
    :ets.match_object(state.spo, {{s, :_, :_}})
    |> Enum.map(fn {{subj, pred, obj}} -> {subj, pred, obj} end)
  end

  # Predicate specified — prefix match on POS index
  defp do_query(state, nil, p, nil) when not is_nil(p) do
    :ets.match_object(state.pos, {{p, :_, :_}})
    |> Enum.map(fn {{_pred, obj, subj}} -> {subj, p, obj} end)
  end

  # Object specified — prefix match on OSP index
  defp do_query(state, nil, nil, o) when not is_nil(o) do
    :ets.match_object(state.osp, {{o, :_, :_}})
    |> Enum.map(fn {{_obj, subj, pred}} -> {subj, pred, o} end)
  end

  # Subject + Predicate — prefix match on SPO index
  defp do_query(state, s, p, nil) when not is_nil(s) and not is_nil(p) do
    :ets.match_object(state.spo, {{s, p, :_}})
    |> Enum.map(fn {{subj, pred, obj}} -> {subj, pred, obj} end)
  end

  # Subject + Object — match on SPO with wildcard predicate
  defp do_query(state, s, nil, o) when not is_nil(s) and not is_nil(o) do
    :ets.match_object(state.spo, {{s, :_, o}})
    |> Enum.map(fn {{subj, pred, obj}} -> {subj, pred, obj} end)
  end

  # Predicate + Object — prefix match on POS index
  defp do_query(state, nil, p, o) when not is_nil(p) and not is_nil(o) do
    :ets.match_object(state.pos, {{p, o, :_}})
    |> Enum.map(fn {{_pred, _obj, subj}} -> {subj, p, o} end)
  end

  # No filters — return all
  defp do_query(state, nil, nil, nil) do
    :ets.tab2list(state.spo)
    |> Enum.map(fn {{s, p, o}} -> {s, p, o} end)
  end

  # --- Journal Persistence ---

  defp journal_write(%{journal_path: nil}, _op, _triple), do: :ok
  defp journal_write(%{journal_path: path}, op, {s, p, o}) do
    line = Jason.encode!(%{op: op, s: s, p: p, o: o}) <> "\n"
    File.write!(path, line, [:append])
  rescue
    e ->
      msg = Exception.message(e)
      Logger.error("[vaos_knowledge] Journal write failed: " <> msg)
      :ok
  end

  defp replay_journal(%{journal_path: nil} = state), do: state
  defp replay_journal(%{journal_path: path} = state) do
    if File.exists?(path) do
      path
      |> File.stream!()
      |> Enum.reduce(state, fn line, acc ->
        case Jason.decode(String.trim(line)) do
          {:ok, %{"op" => "assert", "s" => s, "p" => p, "o" => o}} ->
            :ets.insert(acc.spo, {{s, p, o}})
            :ets.insert(acc.pos, {{p, o, s}})
            :ets.insert(acc.osp, {{o, s, p}})
            acc
          {:ok, %{"op" => "retract", "s" => s, "p" => p, "o" => o}} ->
            :ets.delete(acc.spo, {s, p, o})
            :ets.delete(acc.pos, {p, o, s})
            :ets.delete(acc.osp, {o, s, p})
            acc
          _ -> acc
        end
      end)
    else
      state
    end
  end

  @doc "Compact the journal by rewriting with only current triples."
  def compact_journal(state) do
    if state.journal_path do
      {:ok, triples} = all_triples(state)
      lines = Enum.map(triples, fn {s, p, o} ->
        Jason.encode!(%{op: "assert", s: s, p: p, o: o}) <> "\n"
      end)
      File.write!(state.journal_path, lines)
      {:ok, length(triples)}
    else
      {:ok, 0}
    end
  end

  @doc "Explicitly delete ETS tables when the store is shutting down."
  def cleanup(state) do
    :ets.delete(state.spo)
    :ets.delete(state.pos)
    :ets.delete(state.osp)
    :ok
  end
end
