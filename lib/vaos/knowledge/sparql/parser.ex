defmodule Vaos.Knowledge.Sparql.Parser do
  @moduledoc """
  Parses a subset of SPARQL: SELECT, INSERT DATA, DELETE DATA.
  Supports basic graph patterns, ?variables, ORDER BY, LIMIT.
  """

  @doc "Parse a SPARQL query string into a structured representation."
  def parse(query) when is_binary(query) do
    query = String.trim(query)

    cond do
      query == "" -> {:error, :empty_query}
      query =~ ~r/^SELECT\b/i -> parse_select(query)
      query =~ ~r/^INSERT\s+DATA\b/i -> parse_insert(query)
      query =~ ~r/^DELETE\s+DATA\b/i -> parse_delete(query)
      true -> {:error, :unsupported_query_type}
    end
  end

  # --- SELECT ---

  defp parse_select(query) do
    with {:ok, vars, rest} <- extract_select_vars(query),
         {:ok, patterns, rest} <- extract_where_block(rest),
         {:ok, modifiers} <- extract_modifiers(rest) do
      {:ok,
       %{
         type: :select,
         variables: vars,
         patterns: patterns,
         order_by: modifiers[:order_by],
         limit: modifiers[:limit]
       }}
    end
  end

  defp extract_select_vars(query) do
    case Regex.run(~r/^SELECT\s+(.+?)\s+WHERE\b/is, query) do
      [full_match, var_str] ->
        vars =
          Regex.scan(~r/\?(\w+)/, var_str)
          |> Enum.map(fn [_, name] -> name end)

        rest = String.slice(query, String.length(full_match)..-1//1)
        {:ok, vars, "WHERE" <> rest}

      nil ->
        {:error, :missing_where_clause}
    end
  end

  defp extract_where_block(rest) do
    case Regex.run(~r/WHERE\s*\{(.+?)\}(.*)/is, rest) do
      [_, body, after_block] ->
        patterns = parse_patterns(body)
        {:ok, patterns, String.trim(after_block)}

      nil ->
        {:error, :malformed_where_block}
    end
  end

  defp extract_modifiers(rest) do
    order_by = parse_order_by(rest)
    limit = parse_limit(rest)
    {:ok, %{order_by: order_by, limit: limit}}
  end

  defp parse_order_by(str) do
    case Regex.run(~r/ORDER\s+BY\s+(DESC|ASC)\s*\(?\s*\?(\w+)\s*\)?/i, str) do
      [_, dir, var] ->
        direction = if String.upcase(dir) == "DESC", do: :desc, else: :asc
        {direction, var}

      nil ->
        # Try without direction keyword (defaults to ASC)
        case Regex.run(~r/ORDER\s+BY\s+\(?\s*\?(\w+)\s*\)?/i, str) do
          [_, var] -> {:asc, var}
          nil -> nil
        end
    end
  end

  defp parse_limit(str) do
    case Regex.run(~r/LIMIT\s+(\d+)/i, str) do
      [_, n] -> String.to_integer(n)
      nil -> nil
    end
  end

  # --- INSERT DATA ---

  defp parse_insert(query) do
    case Regex.run(~r/INSERT\s+DATA\s*\{(.+)\}/is, query) do
      [_, body] ->
        triples = parse_triple_data(body)
        {:ok, %{type: :insert_data, triples: triples}}

      nil ->
        {:error, :malformed_insert}
    end
  end

  # --- DELETE DATA ---

  defp parse_delete(query) do
    case Regex.run(~r/DELETE\s+DATA\s*\{(.+)\}/is, query) do
      [_, body] ->
        triples = parse_triple_data(body)
        {:ok, %{type: :delete_data, triples: triples}}

      nil ->
        {:error, :malformed_delete}
    end
  end

  # --- Pattern Parsing ---

  @doc false
  def parse_patterns(body) do
    body
    |> String.trim()
    |> String.split(".")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(&parse_single_pattern/1)
    |> Enum.reject(&is_nil/1)
  end

  defp parse_single_pattern(str) do
    parts = tokenize(str)

    case parts do
      [s, p, o] -> {parse_term(s), parse_term(p), parse_term(o)}
      _ -> nil
    end
  end

  defp parse_triple_data(body) do
    body
    |> String.trim()
    |> String.split(".")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(&parse_data_triple/1)
    |> Enum.reject(&is_nil/1)
  end

  defp parse_data_triple(str) do
    parts = tokenize(str)

    case parts do
      [s, p, o] -> {unwrap_term(s), unwrap_term(p), unwrap_term(o)}
      _ -> nil
    end
  end

  defp tokenize(str) do
    # Match <uri>, ?var, "string", or bare words
    Regex.scan(~r/<[^>]+>|\?[\w]+|"[^"]*"|[\w:\/\.\-]+/, str)
    |> Enum.map(fn [token] -> token end)
  end

  defp parse_term("?" <> name), do: {:var, name}
  defp parse_term("<" <> rest), do: {:literal, String.trim_trailing(rest, ">")}
  defp parse_term("\"" <> rest), do: {:literal, String.trim_trailing(rest, "\"")}
  defp parse_term(other), do: {:literal, other}

  defp unwrap_term("<" <> rest), do: String.trim_trailing(rest, ">")
  defp unwrap_term("\"" <> rest), do: String.trim_trailing(rest, "\"")
  defp unwrap_term(other), do: other
end
