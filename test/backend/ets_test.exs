defmodule Vaos.Knowledge.Backend.ETSTest do
  use ExUnit.Case, async: true

  alias Vaos.Knowledge.Backend.ETS

  setup do
    {:ok, state} = ETS.init(name: :"test_#{System.unique_integer([:positive])}")
    %{state: state}
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
end
