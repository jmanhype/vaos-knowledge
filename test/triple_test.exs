defmodule Vaos.Knowledge.TripleTest do
  use ExUnit.Case, async: true

  alias Vaos.Knowledge.Triple

  describe "new/3" do
    test "creates a valid triple with all fields populated" do
      assert {:ok, triple} = Triple.new("alice", "knows", "bob")
      assert triple.subject == "alice"
      assert triple.predicate == "knows"
      assert triple.object == "bob"
    end

    test "rejects non-string arguments" do
      assert {:error, :invalid_triple} = Triple.new(1, "knows", "bob")
      assert {:error, :invalid_triple} = Triple.new("alice", :knows, "bob")
      assert {:error, :invalid_triple} = Triple.new("alice", "knows", nil)
    end

    test "rejects empty strings" do
      assert {:error, :invalid_triple} = Triple.new("", "knows", "bob")
      assert {:error, :invalid_triple} = Triple.new("alice", "", "bob")
      assert {:error, :invalid_triple} = Triple.new("alice", "knows", "")
    end
  end

  describe "from_tuple/1" do
    test "creates a triple from a 3-tuple" do
      assert {:ok, triple} = Triple.from_tuple({"alice", "knows", "bob"})
      assert triple.subject == "alice"
      assert triple.predicate == "knows"
      assert triple.object == "bob"
    end

    test "rejects non-tuple input" do
      assert {:error, :invalid_triple} = Triple.from_tuple("not a tuple")
      assert {:error, :invalid_triple} = Triple.from_tuple({1, 2})
      assert {:error, :invalid_triple} = Triple.from_tuple(nil)
    end

    test "rejects tuples with empty strings" do
      assert {:error, :invalid_triple} = Triple.from_tuple({"", "knows", "bob"})
    end
  end

  describe "to_tuple/1" do
    test "converts a Triple struct to a raw 3-tuple" do
      {:ok, triple} = Triple.new("alice", "knows", "bob")
      assert Triple.to_tuple(triple) == {"alice", "knows", "bob"}
    end

    test "round-trips through from_tuple and to_tuple" do
      original = {"subject", "predicate", "object"}
      {:ok, triple} = Triple.from_tuple(original)
      assert Triple.to_tuple(triple) == original
    end
  end

  describe "valid?/1" do
    test "returns true for a properly constructed triple" do
      {:ok, triple} = Triple.new("alice", "knows", "bob")
      assert Triple.valid?(triple)
    end

    test "returns false for non-triple structs" do
      refute Triple.valid?(%{subject: "a", predicate: "b", object: "c"})
      refute Triple.valid?(nil)
      refute Triple.valid?("string")
    end

    test "returns false for a Triple with empty subject (constructed via struct directly)" do
      bad = %Triple{subject: "", predicate: "p", object: "o"}
      refute Triple.valid?(bad)
    end

    test "returns false for a Triple with empty predicate" do
      bad = %Triple{subject: "s", predicate: "", object: "o"}
      refute Triple.valid?(bad)
    end

    test "returns false for a Triple with empty object" do
      bad = %Triple{subject: "s", predicate: "p", object: ""}
      refute Triple.valid?(bad)
    end
  end
end
