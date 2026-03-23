defmodule Vaos.Knowledge.Sparql.ExecutorTest do
  use ExUnit.Case

  test "SELECT query execution" do
    name = :"sparql_exec_#{System.unique_integer([:positive])}"
    {:ok, _} = Vaos.Knowledge.open(name)
    :ok = Vaos.Knowledge.assert(name, {"alice", "knows", "bob"})
    :ok = Vaos.Knowledge.assert(name, {"carol", "knows", "dave"})
    {:ok, results} = Vaos.Knowledge.sparql(name, "SELECT ?s ?o WHERE { ?s <knows> ?o }")
    assert length(results) == 2
    assert Enum.all?(results, fn r -> Map.has_key?(r, "s") and Map.has_key?(r, "o") end)
  end

  test "SELECT with ORDER BY and LIMIT" do
    name = :"sparql_order_#{System.unique_integer([:positive])}"
    {:ok, _} = Vaos.Knowledge.open(name)
    :ok = Vaos.Knowledge.assert_many(name, [
      {"pattern:a", "osa:frequency", "10"},
      {"pattern:b", "osa:frequency", "5"},
      {"pattern:c", "osa:frequency", "20"}
    ])
    q = "SELECT ?key ?freq WHERE { ?key <osa:frequency> ?freq } ORDER BY DESC(?freq) LIMIT 2"
    {:ok, results} = Vaos.Knowledge.sparql(name, q)
    assert length(results) == 2
    assert hd(results)["freq"] == "20"
  end

  test "INSERT DATA via SPARQL" do
    name = :"sparql_insert_#{System.unique_integer([:positive])}"
    {:ok, _} = Vaos.Knowledge.open(name)
    {:ok, :inserted, 1} = Vaos.Knowledge.sparql(name, "INSERT DATA { <alice> <knows> <bob> }")
    {:ok, count} = Vaos.Knowledge.count(name)
    assert count == 1
  end

  test "DELETE DATA via SPARQL" do
    name = :"sparql_delete_#{System.unique_integer([:positive])}"
    {:ok, _} = Vaos.Knowledge.open(name)
    :ok = Vaos.Knowledge.assert(name, {"alice", "knows", "bob"})
    {:ok, :deleted, 1} = Vaos.Knowledge.sparql(name, "DELETE DATA { <alice> <knows> <bob> }")
    {:ok, count} = Vaos.Knowledge.count(name)
    assert count == 0
  end

  test "SELECT with multiple patterns (join)" do
    name = :"sparql_join_#{System.unique_integer([:positive])}"
    {:ok, _} = Vaos.Knowledge.open(name)
    :ok = Vaos.Knowledge.assert_many(name, [
      {"alice", "knows", "bob"},
      {"bob", "knows", "carol"}
    ])
    q = "SELECT ?a ?c WHERE { ?a <knows> ?b . ?b <knows> ?c }"
    {:ok, results} = Vaos.Knowledge.sparql(name, q)
    assert length(results) == 1
    assert hd(results)["a"] == "alice"
    assert hd(results)["c"] == "carol"
  end
end
