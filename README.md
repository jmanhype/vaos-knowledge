# vaos-knowledge

ETS-backed triple store with a SPARQL subset parser and OWL 2 RL forward-chaining reasoner. Runs as a GenServer inside the BEAM VM. 11 modules, 1,095 lines of Elixir, 108 tests, 1 dependency (`jason`).

Part of the [VAOS](https://vaos.sh) agent infrastructure. Designed to embed inside an Elixir supervision tree so that agent knowledge bases get OTP crash isolation, zero-copy ETS reads, and in-process reasoning without external triple store dependencies.

| | |
|---|---|
| **Elixir** | >= 1.17 |
| **OTP** | >= 27 |
| **Tests** | 108, 0 failures |
| **Dependencies** | 1 (`jason`) |
| **License** | MIT |

## Table of Contents

- [Architecture](#architecture)
- [ETS 3-Way Indexing](#ets-3-way-indexing)
- [SPARQL Subset](#sparql-subset)
- [OWL 2 RL Reasoning](#owl-2-rl-reasoning)
- [Design Decisions](#design-decisions)
- [Known Limitations](#known-limitations)
- [Installation](#installation)
- [Usage](#usage)
- [Testing](#testing)
- [Project Structure](#project-structure)
- [References](#references)

## Architecture

```
Application (Vaos.Knowledge.Supervisor, :one_for_one)
  |
  +-- Registry (Vaos.Knowledge.Registry)
  |
  +-- DynamicSupervisor (Vaos.Knowledge.StoreSupervisor, :one_for_one)
       |
       +-- Store GenServer (one per named store)
            |-- Backend.ETS (3 ETS tables per store)
            |-- SPARQL.Parser
            |-- SPARQL.Executor
            +-- Reasoner
```

Each named store is a GenServer under the DynamicSupervisor. Stores are independent -- one corrupted store does not crash others. Process naming uses `{:via, Registry, {Vaos.Knowledge.Registry, name}}`, so stores are addressable by string name.

The Store GenServer owns the backend state and delegates:
- Storage operations to `Backend.ETS`
- Query parsing to `SPARQL.Parser`
- Query execution to `SPARQL.Executor`
- Inference to `Reasoner`

## ETS 3-Way Indexing

Each store creates 3 ETS `:set` tables with rotated key orderings of the same triples:

| Table | Key Order | Serves Query Patterns |
|-------|-----------|----------------------|
| SPO | `{subject, predicate, object}` | `{s,p,o}` `{s,p,_}` `{s,_,_}` `{_,_,_}` |
| POS | `{predicate, object, subject}` | `{_,p,o}` `{_,p,_}` |
| OSP | `{object, subject, predicate}` | `{_,_,o}` `{s,_,o}` |

All 8 possible query patterns (2^3 combinations of bound/unbound S, P, O) are covered. Fully-specified lookups use `:ets.lookup/2` (O(1)). Partial matches use `:ets.match_object/2` which scans the relevant index.

**Tradeoff:** 3x storage. Every triple is stored three times. For agent knowledge bases typically under 10,000 triples, this is ~3 MB. Read throughput is ~200,000 pattern matches/sec. The alternative -- a single table with multiple scans -- would halve read performance for the most common query patterns (`{_,p,_}` and `{_,_,o}`).

Table names include a unique timestamp suffix to prevent collision across store restarts: `:"#{name}_spo_#{ts}"`.

Triples are stored as raw 3-tuples internally, not structs. Saves ~40 bytes per triple vs. a `%Triple{}` struct.

## SPARQL Subset

The parser (`sparql/parser.ex`) handles agent-generated SPARQL queries. It is regex-based, not a proper grammar.

**Supported operations:**

| Operation | Syntax | Notes |
|-----------|--------|-------|
| SELECT | `SELECT ?vars WHERE { patterns }` | Basic graph patterns with variables |
| INSERT DATA | `INSERT DATA { triples }` | Assert triples |
| DELETE DATA | `DELETE DATA { triples }` | Retract triples |
| ORDER BY | `ORDER BY ?var` / `ORDER BY ASC(?var)` / `ORDER BY DESC(?var)` | Single variable |
| LIMIT | `LIMIT n` | Integer cap on results |

**Not supported:** OPTIONAL, FILTER, UNION, CONSTRUCT, ASK, DESCRIBE, GROUP BY, HAVING, OFFSET, subqueries, property paths, named graphs, BIND, aggregation functions.

```elixir
{:ok, results} = Vaos.Knowledge.sparql("agent-memory", """
  SELECT ?person ?skill
  WHERE {
    ?person <ex:hasSkill> ?skill .
    ?person <rdf:type> <ex:Developer> .
  }
  ORDER BY ?person
  LIMIT 10
""")
# => [%{"person" => "ex:alice", "skill" => "ex:elixir"}, ...]
```

## OWL 2 RL Reasoning

Forward-chaining materializer that iterates to a fixed point. 4 of ~80 OWL 2 RL rules. Deliberate scope choice -- covers the most commonly useful transitivity and symmetry patterns for agent knowledge bases.

| Rule | Formal Pattern | Infers |
|------|---------------|--------|
| rdfs:subClassOf transitivity | `(A, subClassOf, B)` + `(B, subClassOf, C)` | `(A, subClassOf, C)` |
| owl:inverseOf | `(p, inverseOf, q)` + `(A, p, B)` | `(B, q, A)` |
| owl:TransitiveProperty | `(p, type, TransitiveProperty)` + `(A, p, B)` + `(B, p, C)` | `(A, p, C)` |
| owl:SymmetricProperty | `(p, type, SymmetricProperty)` + `(A, p, B)` | `(B, p, A)` |

Self-loop protection on subClassOf and TransitiveProperty prevents `(A, rel, A)` inferences.

Maximum iteration rounds: 100 (configurable via `:max_rounds` option). Uses `MapSet` for deduplication -- only genuinely new triples are asserted each round.

```elixir
:ok = Vaos.Knowledge.sparql("ontology", """
  INSERT DATA {
    <ex:SeniorDev> <rdfs:subClassOf> <ex:Developer> .
    <ex:Developer> <rdfs:subClassOf> <ex:Employee> .
    <ex:alice> <rdf:type> <ex:SeniorDev> .
  }
""")

{:ok, rounds} = Vaos.Knowledge.materialize("ontology")
# Infers: <ex:SeniorDev> <rdfs:subClassOf> <ex:Employee> (transitivity)
```

## Design Decisions

**GenServer per store.** Crash isolation. One store's bad data or runaway query does not affect other stores. OTP supervisor restarts the failed store. Alternative: single process with namespaced ETS tables. Rejected because it couples failure domains.

**Raw tuples, not structs.** Triples are `{subject, predicate, object}` tuples internally. A `%Triple{}` struct adds ~40 bytes of metadata per triple (struct tag, map overhead). At 10,000 triples across 3 indexes, that is 1.2 MB of overhead for no functional benefit. The `Triple` module exists for validation and construction at the API boundary.

**JSONL journal.** Append-only, one JSON object per line. Human-readable, greppable, trivially debuggable. Recovery is replay: read line by line, apply each operation. Compact with `compact_journal/1` to garbage-collect retracted triples. Tradeoff: synchronous `File.write/3` with `:append` flag limits write throughput to ~5,000 triples/sec. Async writes would 10x this but introduce a crash-loss window.

**Backend behaviour.** `Backend.Behaviour` defines 7 callbacks (`init`, `assert`, `assert_many`, `retract`, `query`, `count`, `all_triples`). ETS is the only implementation today. The behaviour means you could plug in Mnesia (distribution), DETS (disk-backed), or a NIF store without changing the Store GenServer.

**Regex parser over proper grammar.** The SPARQL 1.1 grammar has 170+ production rules. A proper parser (e.g., `nimble_parsec`) would be the right long-term investment. The regex approach was a deliberate scope choice: handles the patterns that agents actually generate (~90% coverage for controlled vocabularies), built in hours instead of weeks. This is technical debt.

## Known Limitations

- **Regex SPARQL parser** (`sparql/parser.ex`): breaks on nested queries, literals with special characters, non-standard whitespace in IRIs. Not a parser -- a pattern matcher for a useful subset. If an agent generates a `FILTER` clause, the parser silently ignores it.
- **O(n^2) reasoner** (`reasoner.ex`): each iteration scans all triples and checks against all schema triples. Under 10,000 triples, materialization completes in milliseconds. Would not scale to millions. A production reasoner needs rule indexing, incremental materialization, or Rete-based evaluation.
- **No named graphs.** All triples live in one default graph per store. If you need graph-level isolation, open a separate store.
- **No blank nodes.** Every node must be a named IRI or string literal. Blank nodes add pattern matching complexity not worth the cost for this use case.
- **Synchronous journal writes** (`backend/ets.ex`): ~5,000 triples/sec ceiling. Adequate for bursty agent workloads, inadequate for bulk loading.
- **4 of ~80 OWL 2 RL rules.** Enough for class hierarchies, inverse/symmetric properties. Not a general-purpose OWL reasoner.

## Installation

As a path dependency (for co-development with other VAOS packages):

```elixir
def deps do
  [
    {:vaos_knowledge, path: "../vaos-knowledge"}
  ]
end
```

Standalone:

```bash
git clone https://github.com/jmanhype/vaos-knowledge.git
cd vaos-knowledge
mix deps.get
mix test
```

## Usage

```elixir
# Open a named store (idempotent -- returns existing pid if already open)
{:ok, _pid} = Vaos.Knowledge.open("agent-memory")

# Assert triples
:ok = Vaos.Knowledge.assert("agent-memory", {"ex:alice", "rdf:type", "ex:Developer"})
:ok = Vaos.Knowledge.assert("agent-memory", {"ex:alice", "ex:hasSkill", "ex:elixir"})

# Bulk assert via SPARQL
:ok = Vaos.Knowledge.sparql("agent-memory", """
  INSERT DATA {
    <ex:bob> <rdf:type> <ex:Developer> .
    <ex:bob> <ex:hasSkill> <ex:rust> .
    <ex:bob> <ex:worksAt> <ex:acme> .
  }
""")

# Query with pattern matching
{:ok, triples} = Vaos.Knowledge.query("agent-memory", predicate: "ex:hasSkill")
# => [{"ex:alice", "ex:hasSkill", "ex:elixir"}, {"ex:bob", "ex:hasSkill", "ex:rust"}]

# Query with SPARQL
{:ok, results} = Vaos.Knowledge.sparql("agent-memory", """
  SELECT ?person ?skill
  WHERE {
    ?person <ex:hasSkill> ?skill .
  }
  ORDER BY ?person
""")

# Run OWL 2 RL reasoning
{:ok, rounds} = Vaos.Knowledge.materialize("agent-memory")

# Get triple count
{:ok, count} = Vaos.Knowledge.count("agent-memory")

# Close store
:ok = Vaos.Knowledge.close("agent-memory")
```

## Testing

```
$ mix test
..............................................................................................................
108 tests, 0 failures
Finished in 0.5 seconds
```

Tests cover: parser (`sparql/parser_test.exs`), executor (`sparql/executor_test.exs`), reasoner (`reasoner_test.exs`), ETS backend (`backend/ets_test.exs`), store GenServer (`store_test.exs`), public API (`knowledge_test.exs`), triple validation (`triple_test.exs`), context (`context_test.exs`).

## Project Structure

```
vaos-knowledge/
  lib/
    vaos/
      knowledge.ex              # Public API facade
      knowledge/
        application.ex          # OTP application, supervision tree
        backend/
          behaviour.ex          # 7-callback backend behaviour
          ets.ex                # ETS implementation, JSONL journal
        context.ex              # Query context
        reasoner.ex             # OWL 2 RL forward-chaining materializer
        registry.ex             # Process registry
        sparql/
          executor.ex           # SPARQL query execution against backend
          parser.ex             # Regex-based SPARQL subset parser
        store.ex                # GenServer per named store
        triple.ex               # Triple validation and construction
  test/
    backend/ets_test.exs
    context_test.exs
    knowledge_test.exs
    reasoner_test.exs
    sparql/
      executor_test.exs
      parser_test.exs
    store_test.exs
    triple_test.exs
  mix.exs
```

## References

- [W3C RDF 1.1 Concepts and Abstract Syntax](https://www.w3.org/TR/rdf11-concepts/)
- [W3C SPARQL 1.1 Query Language](https://www.w3.org/TR/sparql11-query/)
- [W3C OWL 2 Web Ontology Language Profiles -- RL](https://www.w3.org/TR/owl2-profiles/#OWL_2_RL)
- [Erlang ETS Documentation](https://www.erlang.org/doc/man/ets.html)

## License

MIT
