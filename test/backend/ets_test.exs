defmodule Vaos.Knowledge.Backend.ETSTest do
  use ExUnit.Case, async: true

  alias Vaos.Knowledge.Backend.ETS

  setup do
    dir = Path.join(System.tmp_dir!(), "vaos_kg_ets_#{:erlang.phash2(make_ref())}")
    {:ok, state} = ETS.init(name: :"test_#{System.unique_integer([:positive])}", journal_dir: dir)
    %{state: state, journal_dir: dir}
  end

  test "assert and query round-trip", %{state: state} do
    {:ok, state} = ETS.assert(state, {"alice", "knows", "bob"})
    {:ok, results} = ETS.query(state, subject: "alice")
    assert results == [{"alice", "knows", "bob"}]
  end

  test "retract removes from all indexes", %{state: state} do
    {:ok, state} = ETS.assert(state, {"alice", "knows", "bob"})
    {:ok, state} = ETS.retract(state, {"alice", "knows", "bob"})
    {:ok, results} = ETS.query(state, subject: "alice")
    assert results == []
    {:ok, results} = ETS.query(state, predicate: "knows")
    assert results == []
    {:ok, results} = ETS.query(state, object: "bob")
    assert results == []
  end

  test "query by predicate", %{state: state} do
    {:ok, state} = ETS.assert(state, {"alice", "knows", "bob"})
    {:ok, state} = ETS.assert(state, {"carol", "knows", "dave"})
    {:ok, results} = ETS.query(state, predicate: "knows")
    assert length(results) == 2
  end

  test "query by object", %{state: state} do
    {:ok, state} = ETS.assert(state, {"alice", "knows", "bob"})
    {:ok, state} = ETS.assert(state, {"carol", "likes", "bob"})
    {:ok, results} = ETS.query(state, object: "bob")
    assert length(results) == 2
  end

  test "query with subject + predicate", %{state: state} do
    {:ok, state} = ETS.assert(state, {"alice", "knows", "bob"})
    {:ok, state} = ETS.assert(state, {"alice", "likes", "carol"})
    {:ok, results} = ETS.query(state, subject: "alice", predicate: "knows")
    assert results == [{"alice", "knows", "bob"}]
  end

  test "query with all three filters", %{state: state} do
    {:ok, state} = ETS.assert(state, {"alice", "knows", "bob"})
    {:ok, results} = ETS.query(state, subject: "alice", predicate: "knows", object: "bob")
    assert results == [{"alice", "knows", "bob"}]
    {:ok, results} = ETS.query(state, subject: "alice", predicate: "knows", object: "carol")
    assert results == []
  end

  test "query with no filters returns all", %{state: state} do
    {:ok, state} = ETS.assert(state, {"a", "b", "c"})
    {:ok, state} = ETS.assert(state, {"d", "e", "f"})
    {:ok, results} = ETS.query(state, [])
    assert length(results) == 2
  end

  test "query limit bounds a large predicate result set", %{state: state} do
    triples =
      for i <- 1..20 do
        {"subject-#{i}", "summary", "object-#{i}"}
      end

    {:ok, state} = ETS.assert_many(state, triples)
    {:ok, results} = ETS.query(state, [predicate: "summary"], limit: 5)
    assert length(results) == 5
    assert Enum.all?(results, fn {_s, p, _o} -> p == "summary" end)
  end

  test "count returns number of triples", %{state: state} do
    {:ok, count} = ETS.count(state)
    assert count == 0
    {:ok, state} = ETS.assert(state, {"a", "b", "c"})
    {:ok, count} = ETS.count(state)
    assert count == 1
  end

  test "assert_many batch insert", %{state: state} do
    triples = [{"a", "b", "c"}, {"d", "e", "f"}, {"g", "h", "i"}]
    {:ok, state} = ETS.assert_many(state, triples)
    {:ok, count} = ETS.count(state)
    assert count == 3
  end

  test "all_triples returns everything", %{state: state} do
    {:ok, state} = ETS.assert_many(state, [{"a", "b", "c"}, {"d", "e", "f"}])
    {:ok, triples} = ETS.all_triples(state)
    assert length(triples) == 2
  end

  test "duplicate assert is idempotent", %{state: state} do
    {:ok, state} = ETS.assert(state, {"a", "b", "c"})
    {:ok, state} = ETS.assert(state, {"a", "b", "c"})
    {:ok, count} = ETS.count(state)
    assert count == 1
  end

  test "query by predicate + object", %{state: state} do
    {:ok, state} = ETS.assert(state, {"alice", "knows", "bob"})
    {:ok, state} = ETS.assert(state, {"carol", "knows", "bob"})
    {:ok, state} = ETS.assert(state, {"carol", "likes", "bob"})
    {:ok, results} = ETS.query(state, predicate: "knows", object: "bob")
    assert length(results) == 2
  end

  test "query by subject + object", %{state: state} do
    {:ok, state} = ETS.assert(state, {"alice", "knows", "bob"})
    {:ok, state} = ETS.assert(state, {"alice", "likes", "carol"})
    {:ok, results} = ETS.query(state, subject: "alice", object: "bob")
    assert results == [{"alice", "knows", "bob"}]
  end

  test "assert rejects non-binary arguments", %{state: state} do
    assert {:error, :invalid_triple} = ETS.assert(state, {1, "knows", "bob"})
  end

  test "assert_many entries survive journal replay" do
    dir = Path.join(System.tmp_dir!(), "vaos_kg_jrnl_many_#{:erlang.phash2(make_ref())}")
    {:ok, state} = ETS.init(name: :jrnl_many, journal_dir: dir)
    {:ok, _} = ETS.assert_many(state, [{"x", "y", "z"}, {"m", "n", "o"}])
    ETS.cleanup(state)

    {:ok, state2} = ETS.init(name: :jrnl_many, journal_dir: dir)
    {:ok, count} = ETS.count(state2)
    assert count == 2
    {:ok, results} = ETS.query(state2, subject: "x")
    assert results == [{"x", "y", "z"}]
    ETS.cleanup(state2)
    File.rm_rf!(dir)
  end

  test "retract entries are journaled and replayed correctly" do
    dir = Path.join(System.tmp_dir!(), "vaos_kg_retract_#{:erlang.phash2(make_ref())}")
    {:ok, state} = ETS.init(name: :retract_jrnl, journal_dir: dir)
    {:ok, state} = ETS.assert(state, {"a", "b", "c"})
    {:ok, state} = ETS.assert(state, {"d", "e", "f"})
    {:ok, state} = ETS.retract(state, {"a", "b", "c"})
    ETS.cleanup(state)

    {:ok, state2} = ETS.init(name: :retract_jrnl, journal_dir: dir)
    {:ok, count2} = ETS.count(state2)
    assert count2 == 1
    {:ok, results} = ETS.query(state2, [])
    assert results == [{"d", "e", "f"}]
    ETS.cleanup(state2)
    File.rm_rf!(dir)
  end

  test "compact_journal rewrites journal with only current triples" do
    dir = Path.join(System.tmp_dir!(), "vaos_kg_compact_#{:erlang.phash2(make_ref())}")
    {:ok, state} = ETS.init(name: :compact_jrnl, journal_dir: dir)
    {:ok, state} = ETS.assert(state, {"a", "b", "c"})
    {:ok, state} = ETS.assert(state, {"d", "e", "f"})
    {:ok, state} = ETS.retract(state, {"a", "b", "c"})

    ETS.sync(state)
    lines_before = state.journal_path |> File.read!() |> String.split("\n", trim: true)
    assert length(lines_before) == 3

    {:ok, compacted_count} = ETS.compact_journal(state)
    assert compacted_count == 1

    lines_after = state.journal_path |> File.read!() |> String.split("\n", trim: true)
    assert length(lines_after) == 1

    ETS.cleanup(state)
    {:ok, state2} = ETS.init(name: :compact_jrnl, journal_dir: dir)
    {:ok, count} = ETS.count(state2)
    assert count == 1
    ETS.cleanup(state2)
    File.rm_rf!(dir)
  end
end
