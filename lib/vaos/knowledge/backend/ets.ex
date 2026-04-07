defmodule Vaos.Knowledge.Backend.ETS do
  @moduledoc """
  ETS-backed triple store with 3-way indexing (SPO, POS, OSP).
  Provides O(1) lookup on any triple component via :ets.match_object.
  """

  @behaviour Vaos.Knowledge.Backend.Behaviour

  @mix_env Mix.env()

  require Logger

  defstruct [:spo, :pos, :osp, :journal_path, :disk_log]

  @type state :: %__MODULE__{
          spo: :ets.tid(),
          pos: :ets.tid(),
          osp: :ets.tid(),
          disk_log: :disk_log.log() | nil
        }

  @impl true
  @spec init(keyword()) :: {:ok, state()}
  def init(opts) do
    name = Keyword.get(opts, :name, :default)
    ts = System.unique_integer([:positive])
    spo = :ets.new(:"#{name}_spo_#{ts}", [:set, :protected])
    pos = :ets.new(:"#{name}_pos_#{ts}", [:set, :protected])
    osp = :ets.new(:"#{name}_osp_#{ts}", [:set, :protected])

    journal_dir =
      Keyword.get(
        opts,
        :journal_dir,
        if(@mix_env == :test,
          do:
            System.tmp_dir!() <>
              "/vaos_kg_test_" <>
              to_string(System.unique_integer([:positive])) <>
              "_" <> to_string(:os.system_time(:millisecond)),
          else: Path.join(System.user_home!(), ".vaos/knowledge")
        )
      )

    File.mkdir_p!(journal_dir)
    journal_path = Path.join(journal_dir, "#{name}.jsonl")

    disk_log = open_disk_log(name, journal_path)

    state = %__MODULE__{
      spo: spo,
      pos: pos,
      osp: osp,
      journal_path: journal_path,
      disk_log: disk_log
    }

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
    # Batch: insert all into ETS first, then write journal once
    journal_lines =
      Enum.reduce(triples, [], fn triple, acc ->
        case triple do
          {s, p, o} when is_binary(s) and is_binary(p) and is_binary(o) ->
            :ets.insert(state.spo, {{s, p, o}})
            :ets.insert(state.pos, {{p, o, s}})
            :ets.insert(state.osp, {{o, s, p}})
            [Jason.encode!(%{op: "assert", s: s, p: p, o: o}), "\n" | acc]

          _invalid ->
            acc
        end
      end)

    # Single batched journal write
    if journal_lines != [] do
      reversed = Enum.reverse(journal_lines)

      case state.disk_log do
        nil ->
          if state.journal_path, do: File.write!(state.journal_path, reversed, [:append])

        log ->
          :disk_log.blog(log, IO.iodata_to_binary(reversed))
      end
    end

    {:ok, state}
  rescue
    e ->
      Logger.error("[vaos_knowledge] Batched journal write failed: #{Exception.message(e)}")
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
  def query(state, pattern), do: query(state, pattern, [])

  @impl true
  @spec query(state(), keyword(), keyword()) :: {:ok, [Vaos.Knowledge.Backend.Behaviour.triple()]}
  def query(state, pattern, opts) do
    s = Keyword.get(pattern, :subject)
    p = Keyword.get(pattern, :predicate)
    o = Keyword.get(pattern, :object)
    limit = Keyword.get(opts, :limit)

    results = do_query(state, s, p, o, limit)
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
  defp do_query(state, s, p, o, _limit) when not is_nil(s) and not is_nil(p) and not is_nil(o) do
    case :ets.lookup(state.spo, {s, p, o}) do
      [_] -> [{s, p, o}]
      [] -> []
    end
  end

  # Subject specified — prefix match on SPO index
  defp do_query(state, s, nil, nil, limit) when not is_nil(s) do
    limited_index_query(
      state.spo,
      [{{{s, :"$1", :"$2"}}, [], [{{s, :"$1", :"$2"}}]}],
      limit,
      fn ->
        :ets.match_object(state.spo, {{s, :_, :_}})
        |> Enum.map(fn {{subj, pred, obj}} -> {subj, pred, obj} end)
      end
    )
  end

  # Predicate specified — prefix match on POS index
  defp do_query(state, nil, p, nil, limit) when not is_nil(p) do
    limited_index_query(
      state.pos,
      [{{{p, :"$1", :"$2"}}, [], [{{:"$2", p, :"$1"}}]}],
      limit,
      fn ->
        :ets.match_object(state.pos, {{p, :_, :_}})
        |> Enum.map(fn {{_pred, obj, subj}} -> {subj, p, obj} end)
      end
    )
  end

  # Object specified — prefix match on OSP index
  defp do_query(state, nil, nil, o, limit) when not is_nil(o) do
    limited_index_query(
      state.osp,
      [{{{o, :"$1", :"$2"}}, [], [{{:"$1", :"$2", o}}]}],
      limit,
      fn ->
        :ets.match_object(state.osp, {{o, :_, :_}})
        |> Enum.map(fn {{_obj, subj, pred}} -> {subj, pred, o} end)
      end
    )
  end

  # Subject + Predicate — prefix match on SPO index
  defp do_query(state, s, p, nil, limit) when not is_nil(s) and not is_nil(p) do
    limited_index_query(
      state.spo,
      [{{{s, p, :"$1"}}, [], [{{s, p, :"$1"}}]}],
      limit,
      fn ->
        :ets.match_object(state.spo, {{s, p, :_}})
        |> Enum.map(fn {{subj, pred, obj}} -> {subj, pred, obj} end)
      end
    )
  end

  # Subject + Object — match on SPO with wildcard predicate
  defp do_query(state, s, nil, o, limit) when not is_nil(s) and not is_nil(o) do
    limited_index_query(
      state.spo,
      [{{{s, :"$1", o}}, [], [{{s, :"$1", o}}]}],
      limit,
      fn ->
        :ets.match_object(state.spo, {{s, :_, o}})
        |> Enum.map(fn {{subj, pred, obj}} -> {subj, pred, obj} end)
      end
    )
  end

  # Predicate + Object — prefix match on POS index
  defp do_query(state, nil, p, o, limit) when not is_nil(p) and not is_nil(o) do
    limited_index_query(
      state.pos,
      [{{{p, o, :"$1"}}, [], [{{:"$1", p, o}}]}],
      limit,
      fn ->
        :ets.match_object(state.pos, {{p, o, :_}})
        |> Enum.map(fn {{_pred, _obj, subj}} -> {subj, p, o} end)
      end
    )
  end

  # No filters — return all
  defp do_query(state, nil, nil, nil, limit) do
    limited_index_query(
      state.spo,
      [{{{:"$1", :"$2", :"$3"}}, [], [{{:"$1", :"$2", :"$3"}}]}],
      limit,
      fn ->
        :ets.tab2list(state.spo)
        |> Enum.map(fn {{s, p, o}} -> {s, p, o} end)
      end
    )
  end

  defp limited_index_query(_table, _match_spec, limit, _fallback)
       when is_integer(limit) and limit <= 0,
       do: []

  defp limited_index_query(table, match_spec, limit, _fallback_fun)
       when is_integer(limit) and limit > 0 do
    case :ets.select(table, match_spec, limit) do
      :"$end_of_table" ->
        []

      {rows, :"$end_of_table"} ->
        rows

      {rows, continuation} ->
        fill_select_limit(continuation, rows, limit)
    end
  end

  defp limited_index_query(_table, _match_spec, _limit, fallback_fun), do: fallback_fun.()

  defp fill_select_limit(_continuation, rows, limit) when length(rows) >= limit do
    Enum.take(rows, limit)
  end

  defp fill_select_limit(continuation, rows, limit) do
    case :ets.select(continuation) do
      :"$end_of_table" ->
        rows

      {more_rows, :"$end_of_table"} ->
        Enum.take(rows ++ more_rows, limit)

      {more_rows, next_continuation} ->
        combined = rows ++ more_rows

        if length(combined) >= limit do
          Enum.take(combined, limit)
        else
          fill_select_limit(next_continuation, combined, limit)
        end
    end
  end

  # --- Journal Persistence ---

  defp open_disk_log(store_name, journal_path) do
    log_name = String.to_atom("vaos_knowledge_journal_#{store_name}")

    case :disk_log.open(
           name: log_name,
           file: String.to_charlist(journal_path),
           type: :halt,
           format: :external
         ) do
      {:ok, log} ->
        log

      {:repaired, log, _recovered, _bad} ->
        Logger.warning("[vaos_knowledge] Journal disk_log repaired on open")
        log

      {:error, reason} ->
        Logger.error(
          "[vaos_knowledge] Failed to open disk_log: #{inspect(reason)}, falling back to File.write!"
        )

        nil
    end
  end

  defp journal_write(%{disk_log: nil, journal_path: nil}, _op, _triple), do: :ok

  defp journal_write(%{disk_log: nil, journal_path: path}, op, {s, p, o}) do
    # Fallback: synchronous File.write! if disk_log failed to open
    line = Jason.encode!(%{op: op, s: s, p: p, o: o}) <> "\n"
    File.write!(path, line, [:append])
  rescue
    e ->
      Logger.error("[vaos_knowledge] Journal write failed: #{Exception.message(e)}")
      :ok
  end

  defp journal_write(%{disk_log: log}, op, {s, p, o}) do
    line = Jason.encode!(%{op: op, s: s, p: p, o: o}) <> "\n"
    :disk_log.blog(log, line)
  end

  defp journal_sync(%{disk_log: nil}), do: :ok
  defp journal_sync(%{disk_log: log}), do: :disk_log.sync(log)

  defp close_disk_log(%{disk_log: nil}), do: :ok
  defp close_disk_log(%{disk_log: log}), do: :disk_log.close(log)

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

          _ ->
            acc
        end
      end)
    else
      state
    end
  end

  @doc "Flush buffered journal writes to disk."
  def sync(state), do: journal_sync(state)

  @doc "Compact the journal by rewriting with only current triples. Returns `{:ok, count}` for backward compat."
  def compact_journal(state) do
    if state.journal_path do
      # Sync and close disk_log before rewriting the underlying file
      journal_sync(state)
      close_disk_log(state)

      {:ok, triples} = all_triples(state)

      lines =
        Enum.map(triples, fn {s, p, o} ->
          Jason.encode!(%{op: "assert", s: s, p: p, o: o}) <> "\n"
        end)

      File.write!(state.journal_path, lines)

      # Note: disk_log is closed. Caller should re-init or the next write
      # will fall back to synchronous File.write! via the nil disk_log path.
      {:ok, length(triples)}
    else
      {:ok, 0}
    end
  end

  @doc "Explicitly delete ETS tables when the store is shutting down."
  def cleanup(state) do
    journal_sync(state)
    close_disk_log(state)
    :ets.delete(state.spo)
    :ets.delete(state.pos)
    :ets.delete(state.osp)
    :ok
  end
end
