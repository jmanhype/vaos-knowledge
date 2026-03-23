defmodule VaosKnowledge.MixProject do
  use Mix.Project

  @version "0.2.0"
  @source_url "https://github.com/StraughterG/vaos-knowledge"

  def project do
    [
      app: :vaos_knowledge,
      version: @version,
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      # Hex metadata
      name: "VaosKnowledge",
      description: "V.A.O.S. Layer 3: ETS-backed triple store with SPARQL subset and OWL 2 RL reasoning.",
      source_url: @source_url,
      homepage_url: @source_url,
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      docs: [
        main: "Vaos.Knowledge",
        source_ref: "v#{@version}"
      ]
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
