defmodule Vaos.Knowledge.Triple do
  @moduledoc "Triple struct with subject/predicate/object + validation."

  @enforce_keys [:subject, :predicate, :object]
  defstruct [:subject, :predicate, :object]

  @type t :: %__MODULE__{
          subject: String.t(),
          predicate: String.t(),
          object: String.t()
        }

  @doc "Create a new validated triple."
  def new(s, p, o) when is_binary(s) and is_binary(p) and is_binary(o) do
    {:ok, %__MODULE__{subject: s, predicate: p, object: o}}
  end

  def new(_, _, _), do: {:error, :invalid_triple}

  @doc "Create a triple from a 3-tuple."
  def from_tuple({s, p, o}), do: new(s, p, o)
  def from_tuple(_), do: {:error, :invalid_triple}

  @doc "Convert triple to a 3-tuple."
  def to_tuple(%__MODULE__{subject: s, predicate: p, object: o}), do: {s, p, o}

  @doc "Validate that all components are non-empty strings."
  def valid?(%__MODULE__{subject: s, predicate: p, object: o}) do
    s != "" and p != "" and o != ""
  end

  def valid?(_), do: false
end
