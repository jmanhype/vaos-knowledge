defmodule Vaos.Knowledge.Sparql.Executor do
  @moduledoc "Executes parsed SPARQL queries against a backend."

  @type triple :: {String.t(), String.t(), String.t()}
  @type binding :: %{optional(String.t()) => String.t()}

  @doc """
  Execute a parsed query. Returns {result, new_state}.
  result is the value to reply with, new_state is the possibly-updated backend state.
  """
  @spec execute(map(), module(), term()) :: {term(), term()}
  def execute(%{type: :select} = query, backend, state) do
    {:ok, all} = backend.all_triples(state)
    bindings = match_patterns(query.patterns, all)

    # Project selected variables (empty = SELECT *, return all bindings)
    projected =
      case query.variables do
        [] ->
          bindings

        vars ->
          Enum.map(bindings, fn binding ->
            Map.take(binding, vars)
          end)
      end

    # ORDER BY
    projected =
      case query.order_by do
        {direction, var} ->
          sorter = case direction do
            :asc -> :asc
            :desc -> :desc
          end
          Enum.sort_by(projected, fn row ->
            val = Map.get(row, var, "")
            case Integer.parse(to_string(val)) do
              {n, ""} -> {0, n}
              _ -> {1, to_string(val)}
            end
          end, sorter)

        nil ->
          projected
      end

    # LIMIT
    projected =
      case query.limit do
        nil -> projected
        n -> Enum.take(projected, n)
      end

    {{:ok, projected}, state}
  end

  def execute(%{type: :insert_data} = query, backend, state) do
    {:ok, new_state} = backend.assert_many(state, query.triples)
    count = length(query.triples)
    {{:ok, :inserted, count}, new_state}
  end

  def execute(%{type: :delete_data} = query, backend, state) do
    new_state =
      Enum.reduce(query.triples, state, fn triple, acc ->
        {:ok, s} = backend.retract(acc, triple)
        s
      end)

    count = length(query.triples)
    {{:ok, :deleted, count}, new_state}
  end

  # --- Pattern Matching Engine ---

  @spec match_patterns([tuple()], [triple()]) :: [binding()]
  defp match_patterns([], _triples), do: [%{}]

  defp match_patterns([pattern | rest], triples) do
    for binding <- match_patterns(rest, triples),
        triple <- triples,
        new_binding = match_triple(pattern, triple, binding),
        new_binding != nil do
      new_binding
    end
  end

  @spec match_triple(tuple(), triple(), binding()) :: binding() | nil
  defp match_triple({s_pat, p_pat, o_pat}, {s, p, o}, binding) do
    with {:ok, b1} <- bind_term(s_pat, s, binding),
         {:ok, b2} <- bind_term(p_pat, p, b1),
         {:ok, b3} <- bind_term(o_pat, o, b2) do
      b3
    else
      :mismatch -> nil
    end
  end

  @spec bind_term(tuple(), String.t(), binding()) :: {:ok, binding()} | :mismatch
  defp bind_term({:var, name}, value, binding) do
    case Map.get(binding, name) do
      nil -> {:ok, Map.put(binding, name, value)}
      ^value -> {:ok, binding}
      _ -> :mismatch
    end
  end

  defp bind_term({:literal, expected}, value, binding) do
    if expected == value, do: {:ok, binding}, else: :mismatch
  end
end
