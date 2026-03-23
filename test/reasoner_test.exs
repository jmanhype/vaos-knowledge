defmodule Vaos.Knowledge.ReasonerTest do
  use ExUnit.Case

  alias Vaos.Knowledge.Backend.ETS
  alias Vaos.Knowledge.Reasoner

  setup do
    {:ok, state} = ETS.init(name: :"reason_#{System.unique_integer([:positive])}")
    %{state: state}
  end

  describe "subClassOf transitivity" do
    test "infers transitive subclass", %{state: state} do
      {:ok, state} = ETS.assert_many(state, [
        {"Dog", "rdfs:subClassOf", "Animal"},
        {"Puppy", "rdfs:subClassOf", "Dog"}
      ])
      {:ok, state, rounds} = Reasoner.materialize(ETS, state)
      assert rounds >= 1
      {:ok, results} = ETS.query(state, subject: "Puppy", predicate: "rdfs:subClassOf", object: "Animal")
      assert length(results) == 1
    end

    test "multi-hop transitivity infers all intermediate classes", %{state: state} do
      {:ok, state} = ETS.assert_many(state, [
        {"A", "rdfs:subClassOf", "B"},
        {"B", "rdfs:subClassOf", "C"},
        {"C", "rdfs:subClassOf", "D"}
      ])
      {:ok, state, rounds} = Reasoner.materialize(ETS, state)
      assert rounds >= 1
      {:ok, results} = ETS.query(state, subject: "A", predicate: "rdfs:subClassOf", object: "D")
      assert length(results) == 1
    end
  end

  describe "owl:inverseOf" do
    test "infers reverse relationship", %{state: state} do
      {:ok, state} = ETS.assert_many(state, [
        {"knows", "owl:inverseOf", "knownBy"},
        {"alice", "knows", "bob"}
      ])
      {:ok, state, _rounds} = Reasoner.materialize(ETS, state)
      {:ok, results} = ETS.query(state, subject: "bob", predicate: "knownBy", object: "alice")
      assert length(results) == 1
    end
  end

  describe "owl:TransitiveProperty" do
    test "infers transitive chain", %{state: state} do
      {:ok, state} = ETS.assert_many(state, [
        {"isAncestorOf", "rdf:type", "owl:TransitiveProperty"},
        {"grandpa", "isAncestorOf", "dad"},
        {"dad", "isAncestorOf", "child"}
      ])
      {:ok, state, _rounds} = Reasoner.materialize(ETS, state)
      {:ok, results} = ETS.query(state, subject: "grandpa", predicate: "isAncestorOf", object: "child")
      assert length(results) == 1
    end
  end

  describe "owl:SymmetricProperty" do
    test "infers symmetric relationship", %{state: state} do
      {:ok, state} = ETS.assert_many(state, [
        {"friendOf", "rdf:type", "owl:SymmetricProperty"},
        {"alice", "friendOf", "bob"}
      ])
      {:ok, state, _rounds} = Reasoner.materialize(ETS, state)
      {:ok, results} = ETS.query(state, subject: "bob", predicate: "friendOf", object: "alice")
      assert length(results) == 1
    end
  end

  describe "fixpoint behavior" do
    test "empty graph returns 0 rounds", %{state: state} do
      {:ok, _state, rounds} = Reasoner.materialize(ETS, state)
      assert rounds == 0
    end

    test "graph with no applicable rules returns 0 rounds", %{state: state} do
      {:ok, state} = ETS.assert(state, {"a", "b", "c"})
      {:ok, _state, rounds} = Reasoner.materialize(ETS, state)
      assert rounds == 0
    end

    test "respects max_rounds option", %{state: state} do
      {:ok, state} = ETS.assert_many(state, [
        {"A", "rdfs:subClassOf", "B"},
        {"B", "rdfs:subClassOf", "C"},
        {"C", "rdfs:subClassOf", "D"},
        {"D", "rdfs:subClassOf", "E"}
      ])
      {:ok, _state, rounds} = Reasoner.materialize(ETS, state, max_rounds: 1)
      assert rounds <= 1
    end
  end
end
