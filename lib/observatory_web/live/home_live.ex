defmodule ObservatoryWeb.HomeLive do
  @moduledoc """
  Home page - landing page with navigation to analysis tools.
  """
  use ObservatoryWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:current_path, ~p"/")
     |> assign(:page_title, "Home")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <!-- Hero Section -->
      <div class="text-center py-12">
        <div class="mb-6">
          <span class="text-green font-mono text-xs uppercase">[ SYSTEM READY ]</span>
        </div>

        <h2 class="mb-4">
          MEDIA ANALYSIS <span class="text-white">PLATFORM</span>
        </h2>

        <p class="max-w-2xl mx-auto font-mono text-sm">
          Advanced video inspection and GOP structure analysis.<br>
          Upload your media files for comprehensive technical analysis.
        </p>
      </div>

      <!-- Quick Actions -->
      <div class="grid grid-cols-2 gap-6 max-w-3xl mx-auto">
        <.link navigate={~p"/analyze"} class="card p-6">
          <div class="flex items-start gap-4">
            <div class="w-12 h-12 border flex items-center justify-center text-center font-bold">
              [F]
            </div>
            <div>
              <h3 class="mb-1">MEDIA ANALYSIS</h3>
              <p class="font-mono text-sm">Comprehensive codec, format, and stream inspection</p>
            </div>
          </div>
        </.link>

        <.link navigate={~p"/gop"} class="card p-6">
          <div class="flex items-start gap-4">
            <div class="w-12 h-12 border flex items-center justify-center text-center font-bold">
              [G]
            </div>
            <div>
              <h3 class="mb-1">GOP ANALYSIS</h3>
              <p class="font-mono text-sm">Deep inspection of Group of Pictures structure</p>
            </div>
          </div>
        </.link>
      </div>

      <!-- Stats -->
      <div class="border-t pt-8">
        <div class="grid grid-cols-3 gap-8 max-w-2xl mx-auto text-center">
          <div>
            <div class="text-3xl font-bold text-green font-mono mb-1">FFMPEG</div>
            <div class="text-xs text-gray font-mono">POWERED</div>
          </div>
          <div>
            <div class="text-3xl font-bold text-green font-mono mb-1">MEMBRANE</div>
            <div class="text-xs text-gray font-mono">PIPELINE</div>
          </div>
          <div>
            <div class="text-3xl font-bold text-green font-mono mb-1">H.264</div>
            <div class="text-xs text-gray font-mono">CODEC</div>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
