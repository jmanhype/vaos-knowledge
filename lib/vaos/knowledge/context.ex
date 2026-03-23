defmodule Vaos.Knowledge.Context do
  @moduledoc """
  Agent context builder. Extracts scoped triples and renders as markdown prompt.
  Properties: object does NOT contain ":"
  Relationships: object contains ":"
  """

  @doc "Build context for an agent from the store."
  def for_agent(store, opts) do
    agent_id = Keyword.get(opts, :agent_id, "default")
    {:ok, triples} = Vaos.Knowledge.query(store, subject: agent_id)

    {rels, props} =
      Enum.split_with(triples, fn {_s, _p, o} -> String.contains?(o, ":") end)

    properties =
      Enum.map(props, fn {_s, p, o} -> {p, o} end)

    relationships =
      rels
      |> Enum.group_by(fn {_s, p, _o} -> p end, fn {_s, _p, o} -> o end)
      |> Enum.map(fn {p, objects} -> {p, objects} end)

    %{
      agent_id: agent_id,
      properties: properties,
      relationships: relationships,
      count: length(triples)
    }
  end

  @doc "Render context as markdown prompt."
  def to_prompt(ctx) do
    header = "# Knowledge Context (#{ctx.agent_id})\nFacts: #{ctx.count}\n"

    props_section =
      if ctx.properties != [] do
        lines =
          Enum.map(ctx.properties, fn {k, v} -> "  - #{k}: #{v}" end)
          |> Enum.join("\n")

        "\n## Properties\n#{lines}\n"
      else
        ""
      end

    rels_section =
      if ctx.relationships != [] do
        lines =
          Enum.map(ctx.relationships, fn {pred, objects} ->
            "  - #{pred}: #{Enum.join(objects, ", ")}"
          end)
          |> Enum.join("\n")

        "\n## Relationships\n#{lines}\n"
      else
        ""
      end

    header <> props_section <> rels_section
  end
end
