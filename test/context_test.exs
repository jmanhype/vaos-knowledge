defmodule Vaos.Knowledge.ContextTest do
  use ExUnit.Case

  alias Vaos.Knowledge.Context

  setup do
    name = :"ctx_#{System.unique_integer([:positive])}"
    {:ok, _} = Vaos.Knowledge.open(name)
    %{store: name}
  end

  test "for_agent splits properties and relationships", %{store: store} do
    :ok = Vaos.Knowledge.assert_many(store, [
      {"agent1", "role", "admin"},
      {"agent1", "name", "Alice"},
      {"agent1", "knows", "user:bob"},
      {"agent1", "memberOf", "team:alpha"}
    ])

    ctx = Context.for_agent(store, agent_id: "agent1")
    assert ctx.agent_id == "agent1"
    assert ctx.count == 4
    assert length(ctx.properties) == 2
    assert length(ctx.relationships) == 2
  end

  test "to_prompt renders markdown", %{store: store} do
    :ok = Vaos.Knowledge.assert_many(store, [
      {"agent1", "role", "admin"},
      {"agent1", "knows", "user:bob"}
    ])

    ctx = Context.for_agent(store, agent_id: "agent1")
    prompt = Context.to_prompt(ctx)
    assert prompt =~ "# Knowledge Context (agent1)"
    assert prompt =~ "Facts: 2"
    assert prompt =~ "## Properties"
    assert prompt =~ "role: admin"
    assert prompt =~ "## Relationships"
    assert prompt =~ "knows: user:bob"
  end

  test "empty context", %{store: store} do
    ctx = Context.for_agent(store, agent_id: "nobody")
    assert ctx.count == 0
    assert ctx.properties == []
    assert ctx.relationships == []
  end

  test "to_prompt with empty context" do
    ctx = %{agent_id: "empty", properties: [], relationships: [], count: 0}
    prompt = Context.to_prompt(ctx)
    assert prompt =~ "# Knowledge Context (empty)"
    assert prompt =~ "Facts: 0"
    refute prompt =~ "## Properties"
    refute prompt =~ "## Relationships"
  end
end
