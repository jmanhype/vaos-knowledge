# VaosKnowledge

![Elixir](https://img.shields.io/badge/Elixir-1.17%2B-purple)
![OTP](https://img.shields.io/badge/OTP-27%2B-blue)
![License](https://img.shields.io/badge/License-MIT-green)
![Tests](https://img.shields.io/badge/Tests-108%20passing-brightgreen)

ETS-backed triple store implementing a subset of SPARQL 1.1 query language and 4 OWL 2 RL inference rules. 11 modules, 1,095 lines of Elixir, 1 runtime dependency (`jason`). Each named store runs as an isolated GenServer with its own ETS tables and append-only JSONL journal.

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
- [License](#license)

## Architecture

```
Vaos.Knowledge.Supervisor (one_for_one)
├── Vaos.Knowledge.Registry          (Elixir Registry, :unique keys)
└── Vaos.Knowledge.StoreSupervisor   (DynamicSupervisor, one_for_one)
    └── Vaos.Knowledge.Store         (GenServer, one per named store)
        ├── Backend.ETS              (3 ETS tables: SPO, POS, OSP)
        ├── Sparql.Parser            (regex-based SPARQL parser)
        ├── Sparql.Executor          (pattern-matching query engine)
        └── Reasoner                 (forward-chaining materializer)
```

Stores are created on demand via `Store.open/2`, which checks the Registry for an existing process before starting a new child under the DynamicSupervisor. Process naming uses `{:via, Registry, {Vaos.Knowledge.Registry, name}}`. Each store holds a `%{backend: module(), state: backend_state}` map, where `backend` defaults to `Backend.ETS`.

## ETS 3-Way Indexing

Every triple `{subject, predicate, object}` is stored in three ETS `:set` tables, each with a different key rotation. This eliminates the need for secondary indexes or full scans for most query patterns.

**Tables created per store:**

| Table | Key Format | Serves |
|-------|-----------|--------|
| SPO | `{subject, predicate, object}` | S, S+P, S+O, S+P+O queries |
| POS | `{predicate, object, subject}` | P, P+O queries |
| OSP | `{object, subject, predicate}` | O queries |

**Query pattern routing** (8 clauses in `backend/ets.ex:do_query/4`):

| Bound Arguments | Index | ETS Operation | Complexity |
|----------------|-------|---------------|------------|
| S + P + O | SPO | `ets.lookup(spo, {s, p, o})` | O(1) |
| S + P | SPO | `match_object(spo, {{s, p, :_}})` | Prefix match |
| S + O | SPO | `match_object(spo, {{s, :_, o}})` | Wildcard middle |
| S | SPO | `match_object(spo, {{s, :_, :_}})` | Prefix match |
| P + O | POS | `match_object(pos, {{p, o, :_}})` | Prefix match |
| P | POS | `match_object(pos, {{p, :_, :_}})` | Prefix match |
| O | OSP | `match_object(osp, {{o, :_, :_}})` | Prefix match |
| (none) | SPO | `tab2list(spo)` | Full scan |

Every `assert` inserts into all 3 tables; every `retract` deletes from all 3. The triple invariant is maintained by atomic operations within the GenServer's synchronous call handling.

## SPARQL Subset

The parser (`sparql/parser.ex`) uses regex-based tokenization, not a formal grammar. It handles 3 operations:

**Supported:**

| Operation | Syntax | Notes |
|-----------|--------|-------|
| SELECT | `SELECT ?vars WHERE { patterns }` | Basic graph patterns with variable binding |
| INSERT DATA | `INSERT DATA { <s> <p> <o> . }` | Batch triple assertion |
| DELETE DATA | `DELETE DATA { <s> <p> <o> . }` | Batch triple retraction |
| ORDER BY | `ORDER BY [ASC\|DESC](?var)` | Numeric-aware sorting on SELECT |
| LIMIT | `LIMIT n` | Result set truncation |

Terms are parsed as `{:var, name}` for `?variables`, `{:literal, uri}` for `<angle-bracket>` terms, and bare strings for quoted literals and `prefix:local` identifiers.

**Not supported:**

- OPTIONAL, FILTER, UNION
- Aggregation (COUNT, SUM, GROUP BY, HAVING)
- Named graphs (GRAPH, FROM)
- Property paths
- Subqueries
- CONSTRUCT, DESCRIBE, ASK query forms
- Federated queries (SERVICE)

The executor (`sparql/executor.ex`) processes SELECT queries by fetching all triples via `backend.all_triples/1` and running in-memory nested-loop pattern matching with unification semantics. It does not use the indexed `query/2` path. This is a deliberate simplicity tradeoff: multi-pattern basic graph pattern (BGP) joins require cross-pattern variable binding, which the single-pattern index API does not support.

## OWL 2 RL Reasoning

The reasoner (`reasoner.ex`) implements forward-chaining materialization with fixpoint iteration. It runs all rules per round, collects inferred triples, diffs against existing triples, asserts new ones, and repeats until no new triples are produced or `max_rounds` (default 100) is reached.

**4 implemented rules** (of ~80 in the OWL 2 RL profile):

| Rule | Formal Notation | Implementation |
|------|----------------|----------------|
| rdfs:subClassOf transitivity | `(A, subClassOf, B) ^ (B, subClassOf, C) => (A, subClassOf, C)` | O(n^2) pair matching on subClassOf triples |
| owl:inverseOf | `(p, inverseOf, q) ^ (A, p, B) => (B, q, A)` | Finds inverse declarations, flips matching triples |
| owl:TransitiveProperty | `(p, type, TransitiveProperty) ^ (A, p, B) ^ (B, p, C) => (A, p, C)` | O(n^2) pair matching per transitive property |
| owl:SymmetricProperty | `(p, type, SymmetricProperty) ^ (A, p, B) => (B, p, A)` | Swaps subject/object for symmetric properties |

Scope is deliberately limited. These 4 rules cover the most common inference patterns (class hierarchies, inverse/transitive/symmetric relations) without the complexity of full OWL 2 RL (equality reasoning, property chains, class intersections, etc.).

## Design Decisions

**GenServer per store.** Each named store is an isolated process with its own ETS tables. Rationale: crash isolation -- one store's failure does not affect others. Tradeoff: cross-store queries require explicit coordination at the caller level.

**Raw tuples internally.** Triples are stored as `{String.t(), String.t(), String.t()}` tuples, not structs. Rationale: ETS match patterns work directly on tuples, and the 3-element tuple is the minimum representation. The `Triple` module provides validation at the API boundary (`triple.ex`).

**JSONL journal.** Each store appends `{"op":"assert","s":"...","p":"...","o":"..."}` lines to `~/.vaos/knowledge/{name}.jsonl`. Rationale: human-readable, append-only (no write amplification), and trivially replayable. On init, the journal is replayed line-by-line to rebuild ETS state. `compact_journal/1` rewrites with only current live triples. Tradeoff: journal replay time grows linearly with operation history; compaction is manual.

**Backend.Behaviour for swappability.** The 7-callback behaviour (`behaviour.ex`) decouples store logic from storage. Rationale: enables testing with alternative backends and future implementations (e.g., persistent_term, Mnesia, CubDB). Currently only `Backend.ETS` exists. Tradeoff: the abstraction adds one level of indirection to all store operations.

**Synchronous journal writes.** `File.write!(path, line, [:append])` runs inside the GenServer call. Rationale: simplicity over throughput -- writes are ordered and complete before the call returns. Tradeoff: journal I/O is on the critical path for every mutation. A write failure is rescued and logged but does not crash the store.

## Known Limitations

- **Regex parser, no formal grammar** (`sparql/parser.ex`). Splits on `. ` for triple patterns, which can misparse dots inside URIs. Edge cases with nested angle brackets or escaped quotes are not handled. A proper lexer/parser (e.g., NimbleParsec) would fix this.

- **O(n^2) reasoner** (`reasoner.ex`). The transitivity rules compare all pairs of triples with matching predicates per round. For a store with N subClassOf triples, each round is O(N^2). Acceptable for hundreds of triples; problematic for thousands.

- **SELECT fetches all triples** (`sparql/executor.ex`). The executor calls `all_triples/1` and pattern-matches in memory rather than using indexed queries. For large stores, this negates the benefit of 3-way indexing for SPARQL queries.

- **No named graphs or blank nodes.** All triples exist in a single default graph. Blank node identifiers (`_:`) are not generated or handled.

- **No SPARQL FILTER expressions.** There is no expression evaluator for numeric comparisons, string functions, or regex matching within WHERE clauses.

- **Journal compaction is manual.** Without explicit `compact_journal/1` calls, the JSONL file grows monotonically with every assert/retract operation.

## Installation

As a path dependency (co-development):

```elixir
def deps do
  [
    {:vaos_knowledge, path: "../vaos-knowledge"}
  ]
end
```

Standalone:

```bash
git clone <repo-url> vaos-knowledge
cd vaos-knowledge
mix deps.get
mix test
```

Requires Elixir >= 1.17 and OTP >= 27.

## Usage

### Open a Store and Assert Triples

```elixir
# Open a named store (idempotent -- returns existing process if already open)
{:ok, pid} = Vaos.Knowledge.Store.open("my_store")

# Assert individual triples
:ok = Vaos.Knowledge.Store.assert(pid, {"alice", "knows", "bob"})
:ok = Vaos.Knowledge.Store.assert(pid, {"bob", "knows", "charlie"})

# Assert in batch
:ok = Vaos.Knowledge.Store.assert_many(pid, [
  {"alice", "rdf:type", "Person"},
  {"bob", "rdf:type", "Person"}
])
```

### Query with Pattern Matching

```elixir
# Find all triples where alice is the subject
{:ok, triples} = Vaos.Knowledge.Store.query(pid, subject: "alice")

# Find who alice knows
{:ok, triples} = Vaos.Knowledge.Store.query(pid, subject: "alice", predicate: "knows")

# Find all Person-typed entities
{:ok, triples} = Vaos.Knowledge.Store.query(pid, predicate: "rdf:type", object: "Person")
```

### SPARQL Queries

```elixir
{:ok, results} = Vaos.Knowledge.Store.sparql(pid, """
  SELECT ?person ?friend
  WHERE {
    ?person knows ?friend .
  }
  ORDER BY ASC(?person)
  LIMIT 10
""")
# => {:ok, [%{"person" => "alice", "friend" => "bob"}, ...]}
```

### Insert and Delete via SPARQL

```elixir
{:ok, :inserted, 2} = Vaos.Knowledge.Store.sparql(pid, """
  INSERT DATA {
    <charlie> <knows> <dave> .
    <dave> <rdf:type> <Person> .
  }
""")

{:ok, :deleted, 1} = Vaos.Knowledge.Store.sparql(pid, """
  DELETE DATA {
    <charlie> <knows> <dave> .
  }
""")
```

### OWL 2 RL Materialization

```elixir
# Assert class hierarchy
:ok = Vaos.Knowledge.Store.assert(pid, {"Cat", "rdfs:subClassOf", "Animal"})
:ok = Vaos.Knowledge.Store.assert(pid, {"Animal", "rdfs:subClassOf", "LivingThing"})

# Materialize inferred triples
{:ok, count} = Vaos.Knowledge.Store.materialize(pid)
# => {:ok, 1}  (infers Cat rdfs:subClassOf LivingThing)

# Verify the inferred triple
{:ok, [{"Cat", "rdfs:subClassOf", "LivingThing"}]} =
  Vaos.Knowledge.Store.query(pid, subject: "Cat", object: "LivingThing")
```

## Testing

```
$ mix test
..........................................................................
..................................
Finished in 0.6 seconds (0.6s async, 0.00s sync)
108 tests, 0 failures
```

8 test files covering: store operations, ETS backend, SPARQL parser, SPARQL executor, reasoner, triple validation, context builder, and top-level API.

## Project Structure

```
lib/
  vaos/knowledge.ex                     116 lines  Top-level API facade
  vaos/knowledge/
    application.ex                       16 lines  OTP Application, supervision tree
    registry.ex                           7 lines  Process registry (Elixir Registry wrapper)
    store.ex                            178 lines  GenServer: open, assert, query, sparql, materialize
    triple.ex                            42 lines  Triple struct and validation
    reasoner.ex                         123 lines  OWL 2 RL forward-chaining materializer
    context.ex                           94 lines  Agent context builder (properties/relationships)
    backend/
      behaviour.ex                       15 lines  7-callback backend behaviour
      ets.ex                            210 lines  ETS backend: 3-way indexing, JSONL journal
    sparql/
      parser.ex                         182 lines  Regex-based SPARQL tokenizer/parser
      executor.ex                       112 lines  SELECT/INSERT/DELETE execution engine
```

## References

- [RDF 1.1 Concepts and Abstract Syntax](https://www.w3.org/TR/rdf11-concepts/) -- W3C Recommendation, 2014
- [SPARQL 1.1 Query Language](https://www.w3.org/TR/sparql11-query/) -- W3C Recommendation, 2013
- [OWL 2 Web Ontology Language Profiles](https://www.w3.org/TR/owl2-profiles/) -- Section 4: OWL 2 RL
- [Erlang/OTP ETS Reference](https://www.erlang.org/doc/apps/stdlib/ets.html) -- Match specifications and table types

## License

MIT
