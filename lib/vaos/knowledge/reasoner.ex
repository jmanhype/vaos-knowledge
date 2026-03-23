defmodule Vaos.Knowledge.Reasoner do
  @moduledoc """
  OWL 2 RL forward-chaining materializer.
  Implements: rdfs:subClassOf transitivity, owl:inverseOf,
  owl:TransitiveProperty, owl:SymmetricProperty.
  Runs fixpoint iteration until no new triples are inferred.
  """

  @doc """
  Materialize inferred triples. Returns {:ok, new_state, rounds}.
  Accepts opts: [max_rounds: integer] to cap iterations (default 100).
  """
  @max_rounds 100

  def materialize(backend, state, opts \\ []) do
    max = Keyword.get(opts, :max_rounds, @max_rounds)
    do_materialize(backend, state, 0, max)
  end

  defp do_materialize(_backend, state, round, max) when round >= max do
    {:ok, state, round}
  end

  defp do_materialize(backend, state, round, max) do
    {:ok, triples} = backend.all_triples(state)
    triple_set = MapSet.new(triples)
    inferred = infer_all(triples, triple_set)

    new_triples = MapSet.difference(inferred, triple_set) |> MapSet.to_list()

    if new_triples == [] do
      {:ok, state, round}
    else
      {:ok, new_state} = backend.assert_many(state, new_triples)
      do_materialize(backend, new_state, round + 1, max)
    end
  end

  defp infer_all(triples, _existing) do
    new = MapSet.new()
    new = subclass_transitivity(triples, new)
    new = inverse_of(triples, new)
    new = transitive_property(triples, new)
    new = symmetric_property(triples, new)
    new
  end

  # rdfs:subClassOf transitivity:
  # If (A, rdfs:subClassOf, B) and (B, rdfs:subClassOf, C) => (A, rdfs:subClassOf, C)
  defp subclass_transitivity(triples, acc) do
    sub_triples = Enum.filter(triples, fn {_, p, _} -> p == "rdfs:subClassOf" end)

    Enum.reduce(sub_triples, acc, fn {a, _, b}, acc2 ->
      Enum.reduce(sub_triples, acc2, fn {b2, _, c}, acc3 ->
        if b == b2 and a != c do
          MapSet.put(acc3, {a, "rdfs:subClassOf", c})
        else
          acc3
        end
      end)
    end)
  end

  # owl:inverseOf:
  # If (p, owl:inverseOf, q) and (A, p, B) => (B, q, A)
  defp inverse_of(triples, acc) do
    inverse_decls =
      Enum.filter(triples, fn {_, p, _} -> p == "owl:inverseOf" end)
      |> Enum.map(fn {p, _, q} -> {p, q} end)

    Enum.reduce(inverse_decls, acc, fn {p, q}, acc2 ->
      matching = Enum.filter(triples, fn {_, pred, _} -> pred == p end)

      Enum.reduce(matching, acc2, fn {a, _, b}, acc3 ->
        MapSet.put(acc3, {b, q, a})
      end)
    end)
  end

  # owl:TransitiveProperty:
  # If (p, rdf:type, owl:TransitiveProperty) and (A, p, B) and (B, p, C) => (A, p, C)
  defp transitive_property(triples, acc) do
    trans_props =
      Enum.filter(triples, fn {_, p, o} ->
        p == "rdf:type" and o == "owl:TransitiveProperty"
      end)
      |> Enum.map(fn {s, _, _} -> s end)

    Enum.reduce(trans_props, acc, fn prop, acc2 ->
      prop_triples = Enum.filter(triples, fn {_, p, _} -> p == prop end)

      Enum.reduce(prop_triples, acc2, fn {a, _, b}, acc3 ->
        Enum.reduce(prop_triples, acc3, fn {b2, _, c}, acc4 ->
          if b == b2 and a != c do
            MapSet.put(acc4, {a, prop, c})
          else
            acc4
          end
        end)
      end)
    end)
  end

  # owl:SymmetricProperty:
  # If (p, rdf:type, owl:SymmetricProperty) and (A, p, B) => (B, p, A)
  defp symmetric_property(triples, acc) do
    sym_props =
      Enum.filter(triples, fn {_, p, o} ->
        p == "rdf:type" and o == "owl:SymmetricProperty"
      end)
      |> Enum.map(fn {s, _, _} -> s end)

    Enum.reduce(sym_props, acc, fn prop, acc2 ->
      prop_triples = Enum.filter(triples, fn {_, p, _} -> p == prop end)

      Enum.reduce(prop_triples, acc2, fn {a, _, b}, acc3 ->
        MapSet.put(acc3, {b, prop, a})
      end)
    end)
  end
end
