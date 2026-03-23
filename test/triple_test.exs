defmodule Vaos.Knowledge.TripleTest do
  use ExUnit.Case, async: true

  alias Vaos.Knowledge.Triple

  test "new/3 creates a valid triple" do
    assert {:ok, triple} = Triple.new("alice", "knows", "bob")
    assert triple.subject == "alice"
    assert triple.predicate == "knows"
    assert triple.object == "bob"
  end

  test "new/3 rejects non-string arguments" do
    assert {:error, :invalid_triple} = Triple.new(1, "knows", "bob")
    assert {:error, :invalid_triple} = Triple.new("alice", :knows, "bob")
  end

  test "from_tuple/1 creates a triple from tuple" do
    assert {:ok, triple} = Triple.from_tuple({"alice", "knows", "bob"})
    assert triple.subject == "alice"
  end

  test "to_tuple/1 converts triple to tuple" do
    {:ok, triple} = Triple.new("alice", "knows", "bob")
    assert Triple.to_tuple(triple) == {"alice", "knows", "bob"}
  end

  test "valid?/1 checks non-empty strings" do
    {:ok, triple} = Triple.new("alice", "knows", "bob")
    assert Triple.valid?(triple)

    {:ok, empty} = Triple.new("", "knows", "bob")
    refute Triple.valid?(empty)
  end
end
