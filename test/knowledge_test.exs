defmodule Vaos.KnowledgeTest do
  use ExUnit.Case

  test "full API flow" do
    name = :"api_#{System.unique_integer([:positive])}"
    {:ok, _pid} = Vaos.Knowledge.open(name)
    :ok = Vaos.Knowledge.assert(name, {"alice", "knows", "bob"})
    :ok = Vaos.Knowledge.assert(name, {"alice", "age", "30"})
    {:ok, results} = Vaos.Knowledge.query(name, subject: "alice")
    assert length(results) == 2
    {:ok, count} = Vaos.Knowledge.count(name)
    assert count == 2
    :ok = Vaos.Knowledge.retract(name, {"alice", "age", "30"})
    {:ok, count} = Vaos.Knowledge.count(name)
    assert count == 1
  end

  test "assert_many via top-level API" do
    name = :"api_batch_#{System.unique_integer([:positive])}"
    {:ok, _pid} = Vaos.Knowledge.open(name)
    :ok = Vaos.Knowledge.assert_many(name, [{"a", "b", "c"}, {"d", "e", "f"}])
    {:ok, count} = Vaos.Knowledge.count(name)
    assert count == 2
  end

  test "query with no pattern returns all triples" do
    name = :"api_all_#{System.unique_integer([:positive])}"
    {:ok, _pid} = Vaos.Knowledge.open(name)
    :ok = Vaos.Knowledge.assert_many(name, [{"a", "b", "c"}, {"d", "e", "f"}])
    {:ok, results} = Vaos.Knowledge.query(name)
    assert length(results) == 2
  end
end
