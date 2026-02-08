defmodule ObservatoryWeb.Router do
  use ObservatoryWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api", ObservatoryWeb do
    pipe_through :api
  end
end
