defmodule Vaos.Knowledge.StoreTest do
  use ExUnit.Case

  alias Vaos.Knowledge.Store

  setup do
    name = :"store_#{System.unique_integer([:positive])}"
    {:ok, _pid} = Store.open(name)
    %{store: name}
  end

  describe "open/1" do
    test "creates a new named store and returns a pid", %{store: store} do
      # already opened in setup; verify we can use it
      :ok = Store.assert(store, {"a", "b", "c"})
      {:ok, count} = Store.count(store)
      assert count == 1
    end

    test "opening the same name twice returns the same pid" do
      name = :"dup_#{System.unique_integer([:positive])}"
      {:ok, pid1} = Store.open(name)
      {:ok, pid2} = Store.open(name)
      assert pid1 == pid2
    end
  end

  describe "assert/2" do
    test "inserts a triple and query confirms it", %{store: store} do
      :ok = Store.assert(store, {"alice", "knows", "bob"})
      {:ok, results} = Store.query(store, subject: "alice")
      assert results == [{"alice", "knows", "bob"}]
    end

    test "returns error for non-binary triple components", %{store: store} do
      assert {:error, :invalid_triple} = Store.assert(store, {1, "p", "o"})
      assert {:error, :invalid_triple} = Store.assert(store, {"s", :p, "o"})
    end
  end

  describe "assert_many/2" do
    test "inserts multiple triples in one call", %{store: store} do
      :ok = Store.assert_many(store, [{"a", "b", "c"}, {"d", "e", "f"}])
      {:ok, count} = Store.count(store)
      assert count == 2
    end
  end

  describe "retract/2" do
    test "removes an existing triple", %{store: store} do
      :ok = Store.assert(store, {"a", "b", "c"})
      :ok = Store.retract(store, {"a", "b", "c"})
      {:ok, count} = Store.count(store)
      assert count == 0
    end

    test "retracting a non-existent triple is a no-op", %{store: store} do
      :ok = Store.retract(store, {"x", "y", "z"})
      {:ok, count} = Store.count(store)
      assert count == 0
    end
  end

  describe "all_triples/1" do
    test "returns all asserted triples", %{store: store} do
      triples = [{"a", "b", "c"}, {"d", "e", "f"}]
      :ok = Store.assert_many(store, triples)
      {:ok, all} = Store.all_triples(store)
      assert Enum.sort(all) == Enum.sort(triples)
    end

    test "returns empty list for empty store", %{store: store} do
      {:ok, all} = Store.all_triples(store)
      assert all == []
    end
  end

  describe "sparql/2" do
    test "returns error for empty SPARQL string", %{store: store} do
      assert {:error, :empty_query} = Store.sparql(store, "")
    end

    test "returns error for unsupported query type", %{store: store} do
      assert {:error, :unsupported_query_type} = Store.sparql(store, "CONSTRUCT { ?s ?p ?o }")
    end
  end

  describe "materialize/2" do
    test "runs forward-chaining through the store GenServer", %{store: store} do
      :ok = Store.assert_many(store, [
        {"Dog", "rdfs:subClassOf", "Animal"},
        {"Puppy", "rdfs:subClassOf", "Dog"}
      ])
      {:ok, rounds} = Store.materialize(store)
      assert rounds >= 1
      {:ok, results} = Store.query(store, subject: "Puppy", predicate: "rdfs:subClassOf", object: "Animal")
      assert length(results) == 1
    end

    test "materialize with no inference returns 0 rounds", %{store: store} do
      :ok = Store.assert(store, {"a", "b", "c"})
      {:ok, rounds} = Store.materialize(store)
      assert rounds == 0
    end
  end
end
