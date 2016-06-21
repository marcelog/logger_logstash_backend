use Mix.Config

config :logger,
       # disable console backend, so it does not clutter `mix test` output
       backends: []
