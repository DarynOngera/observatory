defmodule ObservatoryWeb.Layouts do
  @moduledoc """
  Terminal-inspired layouts for Observatory.
  """
  use ObservatoryWeb, :html

  import Phoenix.Component

  embed_templates "layouts/*"

  @doc """
  Renders flash notices.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  def flash_group(assigns) do
    ~H"""
    <div id="flash-group">
      <%= if live_flash = @flash["info"] do %>
        <div
          id="flash-info"
          class="flash flash-info mb-4"
          role="alert"
        >
          <div class="flex items-center gap-2">
            <span class="text-green">[INFO]</span>
            <span><%= live_flash %></span>
          </div>
        </div>
      <% end %>

      <%= if live_flash = @flash["error"] do %>
        <div
          id="flash-error"
          class="flash flash-error mb-4"
          role="alert"
        >
          <div class="flex items-center gap-2">
            <span class="text-red">[ERROR]</span>
            <span><%= live_flash %></span>
          </div>
        </div>
      <% end %>
    </div>
    """
  end
end
