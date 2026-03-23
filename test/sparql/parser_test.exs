defmodule Vaos.Knowledge.Sparql.ParserTest do
  use ExUnit.Case, async: true

  alias Vaos.Knowledge.Sparql.Parser

  test "parse SELECT with variables" do
    {:ok, parsed} = Parser.parse("SELECT ?s ?o WHERE { ?s <knows> ?o }")
    assert parsed.type == :select
    assert parsed.variables == ["s", "o"]
    assert length(parsed.patterns) == 1
  end

  test "parse SELECT with ORDER BY DESC and LIMIT" do
    q = "SELECT ?key ?freq WHERE { ?key <osa:frequency> ?freq } ORDER BY DESC(?freq) LIMIT 5"
    {:ok, parsed} = Parser.parse(q)
    assert parsed.type == :select
    assert parsed.order_by == {:desc, "freq"}
    assert parsed.limit == 5
  end

  test "parse INSERT DATA" do
    q = ~s|INSERT DATA { <alice> <knows> <bob> }|
    {:ok, parsed} = Parser.parse(q)
    assert parsed.type == :insert_data
    assert parsed.triples == [{"alice", "knows", "bob"}]
  end

  test "parse INSERT DATA with multiple triples" do
    q = ~s|INSERT DATA { <alice> <knows> <bob> . <carol> <knows> <dave> }|
    {:ok, parsed} = Parser.parse(q)
    assert length(parsed.triples) == 2
  end

  test "parse DELETE DATA" do
    q = ~s|DELETE DATA { <alice> <knows> <bob> }|
    {:ok, parsed} = Parser.parse(q)
    assert parsed.type == :delete_data
    assert parsed.triples == [{"alice", "knows", "bob"}]
  end

  test "unsupported query type" do
    assert {:error, :unsupported_query_type} = Parser.parse("CONSTRUCT { ?s ?p ?o }")
  end

  test "SELECT with literal predicates" do
    q = ~s|SELECT ?err ?sol WHERE { ?err <osa:solution> ?sol }|
    {:ok, parsed} = Parser.parse(q)
    [{s, p, o}] = parsed.patterns
    assert s == {:var, "err"}
    assert p == {:literal, "osa:solution"}
    assert o == {:var, "sol"}
  end
end
