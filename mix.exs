defmodule VaosKnowledge.MixProject do
  use Mix.Project

  def project do
    [
      app: :vaos_knowledge,
      version: "0.1.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      name: "VaosKnowledge",
      description: "V.A.O.S. Layer 3: Triple store with SPARQL and OWL 2 RL reasoning"
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Vaos.Knowledge.Application, []}
    ]
  end

  defp deps do
    [
      {:jason, "~> 1.4"}
    ]
  end
end
