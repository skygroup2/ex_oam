defmodule SknRun.MixProject do
  use Mix.Project

  def project do
    [
      app: :skn_run,
      version: "0.1.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [
        :logger,
        :skn_lib,
        :skn_bot,
        :cq_util,
      ]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:skn_bot, git: "git@github.com:skygroup2/skn_bot.git", branch: "main"},
      {:cq_util, git: "git@github.com:orange-capital/cq-util.ex.git", branch: "main"},
      {:cowboy, "~> 2.11"},
      {:jason, "~> 1.4"}
    ]
  end
end
