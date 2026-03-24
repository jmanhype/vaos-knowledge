defmodule Vaos.Knowledge.ContextTest do
  use ExUnit.Case

  alias Vaos.Knowledge.Context

  setup do
    name = :"ctx_#{System.unique_integer([:positive])}"
    {:ok, _} = Vaos.Knowledge.open(name)
    %{store: name}
  end

  describe "for_agent/2 - property vs relationship classification" do
    test "plain string values are classified as properties", %{store: store} do
      :ok = Vaos.Knowledge.assert_many(store, [
        {"agent1", "role", "admin"},
        {"agent1", "name", "Alice"}
      ])
      ctx = Context.for_agent(store, agent_id: "agent1")
      assert length(ctx.properties) == 2
      assert length(ctx.relationships) == 0
    end

    test "namespace:value patterns are classified as relationships", %{store: store} do
      :ok = Vaos.Knowledge.assert_many(store, [
        {"agent1", "knows", "user:bob"},
        {"agent1", "memberOf", "team:alpha"}
      ])
      ctx = Context.for_agent(store, agent_id: "agent1")
      assert length(ctx.properties) == 0
      assert length(ctx.relationships) == 2
    end

    test "URLs are classified as properties, not relationships", %{store: store} do
      :ok = Vaos.Knowledge.assert_many(store, [
        {"agent1", "homepage", "https://example.com"},
        {"agent1", "avatar", "http://cdn.example.com/img.png"}
      ])
      ctx = Context.for_agent(store, agent_id: "agent1")
      assert length(ctx.properties) == 2
      assert length(ctx.relationships) == 0
    end

    test "timestamps with colons are classified as properties, not relationships", %{store: store} do
      :ok = Vaos.Knowledge.assert_many(store, [
        {"agent1", "created_at", "2024-01-15T08:30:00"},
        {"agent1", "time", "14:30:00"}
      ])
      ctx = Context.for_agent(store, agent_id: "agent1")
      assert length(ctx.properties) == 2
      assert length(ctx.relationships) == 0
    end

    test "HH:MM values are classified as properties, not relationships", %{store: store} do
      :ok = Vaos.Knowledge.assert_many(store, [
        {"agent1", "start_time", "09:30"},
        {"agent1", "end_time", "17:00"}
      ])
      ctx = Context.for_agent(store, agent_id: "agent1")
      assert length(ctx.properties) == 2
      assert length(ctx.relationships) == 0
    end

    test "mixed properties and relationships", %{store: store} do
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

    test "empty context for unknown agent", %{store: store} do
      ctx = Context.for_agent(store, agent_id: "nobody")
      assert ctx.count == 0
      assert ctx.properties == []
      assert ctx.relationships == []
    end

    test "localhost:4000 is classified as a property, not a relationship", %{store: store} do
      :ok = Vaos.Knowledge.assert(store, {"agent1", "endpoint", "localhost:4000"})
      ctx = Context.for_agent(store, agent_id: "agent1")
      assert length(ctx.properties) == 1
      assert length(ctx.relationships) == 0
    end

    test "host:port patterns with numeric ports are properties", %{store: store} do
      :ok = Vaos.Knowledge.assert_many(store, [
        {"agent1", "redis", "redis:6379"},
        {"agent1", "db", "postgres:5432"}
      ])
      ctx = Context.for_agent(store, agent_id: "agent1")
      assert length(ctx.properties) == 2
      assert length(ctx.relationships) == 0
    end

    test "rdf:type is still a relationship", %{store: store} do
      :ok = Vaos.Knowledge.assert(store, {"agent1", "type", "rdf:type"})
      ctx = Context.for_agent(store, agent_id: "agent1")
      assert length(ctx.relationships) == 1
      assert length(ctx.properties) == 0
    end
  end

  describe "to_prompt/1" do
    test "renders full markdown with properties and relationships", %{store: store} do
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

    test "omits sections when empty" do
      ctx = %{agent_id: "empty", properties: [], relationships: [], count: 0}
      prompt = Context.to_prompt(ctx)
      assert prompt =~ "# Knowledge Context (empty)"
      assert prompt =~ "Facts: 0"
      refute prompt =~ "## Properties"
      refute prompt =~ "## Relationships"
    end

    test "renders only properties when no relationships" do
      ctx = %{agent_id: "x", properties: [{"role", "admin"}], relationships: [], count: 1}
      prompt = Context.to_prompt(ctx)
      assert prompt =~ "## Properties"
      refute prompt =~ "## Relationships"
    end

    test "renders only relationships when no properties" do
      ctx = %{agent_id: "x", properties: [], relationships: [{"knows", ["user:bob"]}], count: 1}
      prompt = Context.to_prompt(ctx)
      refute prompt =~ "## Properties"
      assert prompt =~ "## Relationships"
      assert prompt =~ "knows: user:bob"
    end
  end
end
