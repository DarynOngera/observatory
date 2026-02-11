defmodule ObservatoryWeb.Router do
  use ObservatoryWeb, :router

  import Phoenix.LiveView.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, {ObservatoryWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", ObservatoryWeb do
    pipe_through :browser

    live "/", HomeLive, :index
    live "/analyze", AnalyzeLive, :index
    live "/gop", GopLive, :index
  end

  scope "/api", ObservatoryWeb do
    pipe_through :api
  end
end
