defmodule Vaos.Knowledge.Sparql.ParserTest do
  use ExUnit.Case, async: true

  alias Vaos.Knowledge.Sparql.Parser

  describe "SELECT" do
    test "parses variables and a single pattern" do
      {:ok, parsed} = Parser.parse("SELECT ?s ?o WHERE { ?s <knows> ?o }")
      assert parsed.type == :select
      assert parsed.variables == ["s", "o"]
      assert length(parsed.patterns) == 1
      [{s, p, o}] = parsed.patterns
      assert s == {:var, "s"}
      assert p == {:literal, "knows"}
      assert o == {:var, "o"}
    end

    test "parses ORDER BY DESC and LIMIT" do
      q = "SELECT ?key ?freq WHERE { ?key <osa:frequency> ?freq } ORDER BY DESC(?freq) LIMIT 5"
      {:ok, parsed} = Parser.parse(q)
      assert parsed.type == :select
      assert parsed.order_by == {:desc, "freq"}
      assert parsed.limit == 5
    end

    test "parses ORDER BY without direction, defaults to ASC" do
      q = "SELECT ?s ?o WHERE { ?s <knows> ?o } ORDER BY ?s"
      {:ok, parsed} = Parser.parse(q)
      assert parsed.order_by == {:asc, "s"}
    end

    test "parses SELECT with literal predicates (namespace style)" do
      q = ~s|SELECT ?err ?sol WHERE { ?err <osa:solution> ?sol }|
      {:ok, parsed} = Parser.parse(q)
      [{s, p, o}] = parsed.patterns
      assert s == {:var, "err"}
      assert p == {:literal, "osa:solution"}
      assert o == {:var, "sol"}
    end

    test "parses multiple patterns (join)" do
      q = "SELECT ?a ?b ?c WHERE { ?a <knows> ?b . ?b <knows> ?c }"
      {:ok, parsed} = Parser.parse(q)
      assert length(parsed.patterns) == 2
    end

    test "returns error for missing WHERE clause" do
      assert {:error, :missing_where_clause} = Parser.parse("SELECT ?s")
    end
  end

  describe "INSERT DATA" do
    test "parses a single triple" do
      q = ~s|INSERT DATA { <alice> <knows> <bob> }|
      {:ok, parsed} = Parser.parse(q)
      assert parsed.type == :insert_data
      assert parsed.triples == [{"alice", "knows", "bob"}]
    end

    test "parses multiple triples" do
      q = ~s|INSERT DATA { <alice> <knows> <bob> . <carol> <knows> <dave> }|
      {:ok, parsed} = Parser.parse(q)
      assert length(parsed.triples) == 2
      assert {"alice", "knows", "bob"} in parsed.triples
      assert {"carol", "knows", "dave"} in parsed.triples
    end
  end

  describe "DELETE DATA" do
    test "parses a single triple" do
      q = ~s|DELETE DATA { <alice> <knows> <bob> }|
      {:ok, parsed} = Parser.parse(q)
      assert parsed.type == :delete_data
      assert parsed.triples == [{"alice", "knows", "bob"}]
    end
  end

  describe "error cases" do
    test "empty string returns empty_query error" do
      assert {:error, :empty_query} = Parser.parse("")
      assert {:error, :empty_query} = Parser.parse("   ")
    end

    test "unsupported query type returns error" do
      assert {:error, :unsupported_query_type} = Parser.parse("CONSTRUCT { ?s ?p ?o }")
      assert {:error, :unsupported_query_type} = Parser.parse("ASK { ?s ?p ?o }")
    end
  end
end
