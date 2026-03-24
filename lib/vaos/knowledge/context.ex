defmodule Vaos.Knowledge.Context do
  @moduledoc """
  Agent context builder. Extracts scoped triples and renders as markdown prompt.

  Classification heuristic:
  - Relationship: object matches "prefix:localname" where prefix and localname
    are non-empty, contain no spaces or slashes, and there is exactly one colon.
    Examples: "user:bob", "team:alpha", "rdf:type".
    NOT matched: URLs ("http://..."), timestamps ("2024-01:00"), values with spaces,
    host:port patterns ("localhost:4000").
  - Property: everything else (plain strings, URLs, numbers, timestamps).
  """

  @doc "Build context for an agent from the store."
  def for_agent(store, opts) do
    agent_id = Keyword.get(opts, :agent_id, "default")

    {:ok, triples} = Vaos.Knowledge.query(store, subject: agent_id)

    {rels, props} =
      Enum.split_with(triples, fn {_s, _p, o} -> namespace_ref?(o) end)

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

  # A namespace reference looks like "prefix:localname" where:
  # - exactly one colon
  # - no slashes (rules out URLs like http://... or https://...)
  # - no spaces in either part
  # - both prefix and localname are non-empty
  # - prefix starts with a letter
  # - localname has no further colons (rules out "HH:MM:SS" timestamps)
  # - localname is NOT purely numeric (rules out "localhost:4000" host:port patterns)
  defp namespace_ref?(value) when is_binary(value) do
    case String.split(value, ":", parts: 2) do
      [prefix, local] ->
        prefix != "" and
          local != "" and
          String.match?(prefix, ~r/^[a-zA-Z]/) and
          not String.contains?(prefix, ["/", " "]) and
          not String.contains?(local, ["/", " ", ":"]) and
          not String.match?(local, ~r/^\d+$/)

      _ ->
        false
    end
  end

  defp namespace_ref?(_), do: false
end
