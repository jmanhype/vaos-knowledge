defmodule Vaos.KnowledgeTest do
  use ExUnit.Case

  describe "full lifecycle" do
    test "open, assert, query, retract, count" do
      name = :"api_#{System.unique_integer([:positive])}"
      {:ok, _pid} = Vaos.Knowledge.open(name)
      :ok = Vaos.Knowledge.assert(name, {"alice", "knows", "bob"})
      :ok = Vaos.Knowledge.assert(name, {"alice", "age", "30"})

      {:ok, results} = Vaos.Knowledge.query(name, subject: "alice")
      assert length(results) == 2
      assert {"alice", "knows", "bob"} in results
      assert {"alice", "age", "30"} in results

      {:ok, count} = Vaos.Knowledge.count(name)
      assert count == 2

      :ok = Vaos.Knowledge.retract(name, {"alice", "age", "30"})
      {:ok, count} = Vaos.Knowledge.count(name)
      assert count == 1
    end
  end

  describe "assert/2 error paths" do
    test "rejects non-binary triple at top-level API" do
      name = :"api_err_#{System.unique_integer([:positive])}"
      {:ok, _} = Vaos.Knowledge.open(name)
      assert {:error, :invalid_triple} = Vaos.Knowledge.assert(name, {1, "p", "o"})
      assert {:error, :invalid_triple} = Vaos.Knowledge.assert(name, "not a triple")
    end

    test "rejects empty string triple components" do
      name = :"api_empty_#{System.unique_integer([:positive])}"
      {:ok, _} = Vaos.Knowledge.open(name)
      assert {:error, :invalid_triple} = Vaos.Knowledge.assert(name, {"", "p", "o"})
      assert {:error, :invalid_triple} = Vaos.Knowledge.assert(name, {"s", "", "o"})
      assert {:error, :invalid_triple} = Vaos.Knowledge.assert(name, {"s", "p", ""})
    end
  end

  describe "assert_many/2" do
    test "batch inserts triples" do
      name = :"api_batch_#{System.unique_integer([:positive])}"
      {:ok, _pid} = Vaos.Knowledge.open(name)
      :ok = Vaos.Knowledge.assert_many(name, [{"a", "b", "c"}, {"d", "e", "f"}])
      {:ok, count} = Vaos.Knowledge.count(name)
      assert count == 2
    end
  end

  describe "query/2" do
    test "no pattern returns all triples" do
      name = :"api_all_#{System.unique_integer([:positive])}"
      {:ok, _pid} = Vaos.Knowledge.open(name)
      :ok = Vaos.Knowledge.assert_many(name, [{"a", "b", "c"}, {"d", "e", "f"}])
      {:ok, results} = Vaos.Knowledge.query(name)
      assert length(results) == 2
    end

    test "query by predicate" do
      name = :"api_pred_#{System.unique_integer([:positive])}"
      {:ok, _} = Vaos.Knowledge.open(name)
      :ok = Vaos.Knowledge.assert_many(name, [
        {"alice", "knows", "bob"},
        {"alice", "likes", "carol"}
      ])
      {:ok, results} = Vaos.Knowledge.query(name, predicate: "knows")
      assert results == [{"alice", "knows", "bob"}]
    end
  end

  describe "all_triples/1" do
    test "returns all triples in the store" do
      name = :"api_alltriples_#{System.unique_integer([:positive])}"
      {:ok, _} = Vaos.Knowledge.open(name)
      triples = [{"a", "b", "c"}, {"d", "e", "f"}]
      :ok = Vaos.Knowledge.assert_many(name, triples)
      {:ok, all} = Vaos.Knowledge.all_triples(name)
      assert Enum.sort(all) == Enum.sort(triples)
    end
  end

  describe "materialize/1" do
    test "forward-chains OWL 2 RL rules through the store" do
      name = :"api_mat_#{System.unique_integer([:positive])}"
      {:ok, _} = Vaos.Knowledge.open(name)
      :ok = Vaos.Knowledge.assert_many(name, [
        {"A", "rdfs:subClassOf", "B"},
        {"B", "rdfs:subClassOf", "C"}
      ])
      {:ok, rounds} = Vaos.Knowledge.materialize(name)
      assert rounds >= 1
      {:ok, results} = Vaos.Knowledge.query(name, subject: "A", predicate: "rdfs:subClassOf", object: "C")
      assert length(results) == 1
    end
  end

  describe "sparql/2" do
    test "SELECT query returns results" do
      name = :"api_sparql_#{System.unique_integer([:positive])}"
      {:ok, _} = Vaos.Knowledge.open(name)
      :ok = Vaos.Knowledge.assert(name, {"alice", "knows", "bob"})
      {:ok, results} = Vaos.Knowledge.sparql(name, "SELECT ?s ?o WHERE { ?s <knows> ?o }")
      assert length(results) == 1
      assert hd(results)["s"] == "alice"
      assert hd(results)["o"] == "bob"
    end

    test "returns error for empty SPARQL" do
      name = :"api_sparql_err_#{System.unique_integer([:positive])}"
      {:ok, _} = Vaos.Knowledge.open(name)
      assert {:error, :empty_query} = Vaos.Knowledge.sparql(name, "")
    end
  end

  describe "sparql/2 input validation" do
    test "rejects non-binary query at top-level API" do
      name = :"api_sparql_guard_\#{System.unique_integer([:positive])}"
      {:ok, _} = Vaos.Knowledge.open(name)
      assert {:error, :invalid_query} = Vaos.Knowledge.sparql(name, 123)
      assert {:error, :invalid_query} = Vaos.Knowledge.sparql(name, nil)
      assert {:error, :invalid_query} = Vaos.Knowledge.sparql(name, :atom)
      assert {:error, :invalid_query} = Vaos.Knowledge.sparql(name, ["list"])
    end

    test "binary query still works normally" do
      name = :"api_sparql_ok_\#{System.unique_integer([:positive])}"
      {:ok, _} = Vaos.Knowledge.open(name)
      :ok = Vaos.Knowledge.assert(name, {"a", "b", "c"})
      {:ok, results} = Vaos.Knowledge.sparql(name, "SELECT ?s WHERE { ?s <b> <c> }")
      assert length(results) == 1
    end
  end

  describe "store_ref/1" do
    test "returns name when store is open" do
      name = :"api_ref_#{System.unique_integer([:positive])}"
      {:ok, _} = Vaos.Knowledge.open(name)
      assert Vaos.Knowledge.store_ref(name) == name
    end

    test "returns error when store is not open" do
      assert {:error, :store_not_found} = Vaos.Knowledge.store_ref("nonexistent_store_xyz")
    end
  end

  describe "close/1" do
    test "closes an open store" do
      name = "close_test_#{System.unique_integer([:positive])}"
      {:ok, _} = Vaos.Knowledge.open(name)
      :ok = Vaos.Knowledge.assert(name, {"a", "b", "c"})
      assert :ok = Vaos.Knowledge.close(name)
      Process.sleep(50)
      # Store is gone — store_ref should fail
      assert {:error, :store_not_found} = Vaos.Knowledge.store_ref(name)
    end

    test "returns error for unknown store" do
      assert {:error, :not_found} = Vaos.Knowledge.close("nonexistent_close_xyz")
    end
  end

  describe "SPARQL with URI predicates (dot-in-URI regression)" do
    test "SELECT with http:// predicate" do
      name = :"api_uri_\#{System.unique_integer([:positive])}"
      {:ok, _} = Vaos.Knowledge.open(name)
      :ok = Vaos.Knowledge.assert(name, {"alice", "http://schema.org/knows", "bob"})
      {:ok, results} = Vaos.Knowledge.sparql(name, "SELECT ?s ?o WHERE { ?s <http://schema.org/knows> ?o }")
      assert length(results) == 1
      assert hd(results)["s"] == "alice"
    end

    test "INSERT DATA with dotted URIs round-trips" do
      name = :"api_uri_ins_\#{System.unique_integer([:positive])}"
      {:ok, _} = Vaos.Knowledge.open(name)
      {:ok, :inserted, 1} = Vaos.Knowledge.sparql(name, "INSERT DATA { <http://ex.co/a> <http://ex.co/b> <http://ex.co/c> }")
      {:ok, count} = Vaos.Knowledge.count(name)
      assert count == 1
    end
  end

end
