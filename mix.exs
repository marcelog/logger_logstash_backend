defmodule LoggerLogstashBackend.Mixfile do
  use Mix.Project

  def project do
    [
      app: :logger_logstash_backend,
      name: "logger_logstash_backend",
      source_url: "https://github.com/marcelog/logger_logstash_backend",
      version: "5.0.0",
      elixir: "~> 1.3",
      description: description(),
      package: package(),
      deps: deps()
    ]
  end

  def application do
    [applications: [:logger, :timex, :exjsx]]
  end

  defp deps do
    [
      {:earmark, "~> 1.0.3", only: :dev},
      {:ex_doc, "~> 0.14.5", only: :dev},
      {:exjsx, "~> 4.0.0"},
      {:timex, "~> 3.4.1"}
    ]
  end

  defp description do
    """
    Logstash UDP producer backend for Logger.
    """
  end

  defp package do
    [
      files: ["lib", "mix.exs", "README*", "LICENSE*"],
      maintainers: ["Marcelo Gornstein"],
      licenses: ["Apache 2.0"],
      links: %{
        "GitHub" => "https://github.com/marcelog/logger_logstash_backend"
      }
    ]
  end
end
