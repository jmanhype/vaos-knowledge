defmodule Vaos.Knowledge.StoreTest do
  use ExUnit.Case

  alias Vaos.Knowledge.Store

  setup do
    name = :"store_#{System.unique_integer([:positive])}"
    {:ok, _pid} = Store.open(name)
    %{store: name}
  end

  test "open creates a named store", %{store: store} do
    :ok = Store.assert(store, {"alice", "knows", "bob"})
    {:ok, results} = Store.query(store, subject: "alice")
    assert results == [{"alice", "knows", "bob"}]
  end

  test "open same name returns existing store" do
    name = :"dup_test_#{System.unique_integer([:positive])}"
    {:ok, pid1} = Store.open(name)
    {:ok, pid2} = Store.open(name)
    assert pid1 == pid2
  end

  test "assert_many works through store", %{store: store} do
    :ok = Store.assert_many(store, [{"a", "b", "c"}, {"d", "e", "f"}])
    {:ok, count} = Store.count(store)
    assert count == 2
  end

  test "retract works through store", %{store: store} do
    :ok = Store.assert(store, {"a", "b", "c"})
    :ok = Store.retract(store, {"a", "b", "c"})
    {:ok, count} = Store.count(store)
    assert count == 0
  end
end
