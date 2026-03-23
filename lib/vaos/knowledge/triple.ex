defmodule Vaos.Knowledge.Triple do
  @moduledoc """
  Thin wrapper struct for {subject, predicate, object} triples.

  Used at API boundaries for validation. Internal pipelines (Store, Backend,
  Reasoner) use raw {s, p, o} tuples throughout for efficiency. Triple provides
  from_tuple/to_tuple for conversion and valid?/1 for boundary checks.
  """

  @enforce_keys [:subject, :predicate, :object]
  defstruct [:subject, :predicate, :object]

  @type t :: %__MODULE__{
          subject: String.t(),
          predicate: String.t(),
          object: String.t()
        }

  @doc "Create a new Triple. All fields must be non-empty binary strings."
  def new(s, p, o)
      when is_binary(s) and is_binary(p) and is_binary(o) and
             s != "" and p != "" and o != "" do
    {:ok, %__MODULE__{subject: s, predicate: p, object: o}}
  end

  def new(_, _, _), do: {:error, :invalid_triple}

  @doc "Create a Triple from a raw {s, p, o} tuple."
  def from_tuple({s, p, o}), do: new(s, p, o)
  def from_tuple(_), do: {:error, :invalid_triple}

  @doc "Convert a Triple struct to a raw {s, p, o} tuple."
  def to_tuple(%__MODULE__{subject: s, predicate: p, object: o}), do: {s, p, o}

  @doc "Check that a Triple struct has all non-empty string fields."
  def valid?(%__MODULE__{subject: s, predicate: p, object: o})
      when is_binary(s) and is_binary(p) and is_binary(o) do
    s != "" and p != "" and o != ""
  end

  def valid?(_), do: false
end
