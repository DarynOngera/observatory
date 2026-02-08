defmodule Observatory.Repo do
  use Ecto.Repo,
    otp_app: :observatory,
    adapter: Ecto.Adapters.Postgres
end
