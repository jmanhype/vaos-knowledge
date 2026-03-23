defmodule Vaos.Knowledge.Sparql.ExecutorTest do
  use ExUnit.Case

  describe "SELECT" do
    test "returns bindings for matched variables" do
      name = :"sparql_exec_#{System.unique_integer([:positive])}"
      {:ok, _} = Vaos.Knowledge.open(name)
      :ok = Vaos.Knowledge.assert(name, {"alice", "knows", "bob"})
      :ok = Vaos.Knowledge.assert(name, {"carol", "knows", "dave"})
      {:ok, results} = Vaos.Knowledge.sparql(name, "SELECT ?s ?o WHERE { ?s <knows> ?o }")
      assert length(results) == 2
      assert Enum.all?(results, fn r -> Map.has_key?(r, "s") and Map.has_key?(r, "o") end)
      subjects = Enum.map(results, & &1["s"]) |> Enum.sort()
      assert subjects == ["alice", "carol"]
    end

    test "ORDER BY DESC with LIMIT returns top-N by value" do
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

    test "multi-pattern join resolves variable bindings across patterns" do
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

    test "SELECT * returns all bindings" do
      name = :"sparql_star_#{System.unique_integer([:positive])}"
      {:ok, _} = Vaos.Knowledge.open(name)
      :ok = Vaos.Knowledge.assert(name, {"alice", "knows", "bob"})
      {:ok, results} = Vaos.Knowledge.sparql(name, "SELECT * WHERE { ?s <knows> ?o }")
      assert length(results) == 1
      row = hd(results)
      assert row["s"] == "alice"
      assert row["o"] == "bob"
    end

    test "SELECT with no matches returns empty list" do
      name = :"sparql_empty_#{System.unique_integer([:positive])}"
      {:ok, _} = Vaos.Knowledge.open(name)
      {:ok, results} = Vaos.Knowledge.sparql(name, "SELECT ?s ?o WHERE { ?s <likes> ?o }")
      assert results == []
    end
  end

  describe "INSERT DATA" do
    test "inserts triples and reports count" do
      name = :"sparql_insert_#{System.unique_integer([:positive])}"
      {:ok, _} = Vaos.Knowledge.open(name)
      {:ok, :inserted, 1} = Vaos.Knowledge.sparql(name, "INSERT DATA { <alice> <knows> <bob> }")
      {:ok, count} = Vaos.Knowledge.count(name)
      assert count == 1
    end

    test "inserts multiple triples" do
      name = :"sparql_insert2_#{System.unique_integer([:positive])}"
      {:ok, _} = Vaos.Knowledge.open(name)
      {:ok, :inserted, 2} = Vaos.Knowledge.sparql(name, "INSERT DATA { <a> <b> <c> . <d> <e> <f> }")
      {:ok, count} = Vaos.Knowledge.count(name)
      assert count == 2
    end
  end

  describe "DELETE DATA" do
    test "deletes an existing triple and reports count" do
      name = :"sparql_delete_#{System.unique_integer([:positive])}"
      {:ok, _} = Vaos.Knowledge.open(name)
      :ok = Vaos.Knowledge.assert(name, {"alice", "knows", "bob"})
      {:ok, :deleted, 1} = Vaos.Knowledge.sparql(name, "DELETE DATA { <alice> <knows> <bob> }")
      {:ok, count} = Vaos.Knowledge.count(name)
      assert count == 0
    end
  end

  describe "error handling" do
    test "empty query returns error" do
      name = :"sparql_err_#{System.unique_integer([:positive])}"
      {:ok, _} = Vaos.Knowledge.open(name)
      assert {:error, :empty_query} = Vaos.Knowledge.sparql(name, "")
    end

    test "unsupported query type returns error" do
      name = :"sparql_err2_#{System.unique_integer([:positive])}"
      {:ok, _} = Vaos.Knowledge.open(name)
      assert {:error, :unsupported_query_type} = Vaos.Knowledge.sparql(name, "CONSTRUCT { ?s ?p ?o }")
    end
  end
end
