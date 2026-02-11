defmodule ObservatoryWeb.HomeLive do
  @moduledoc """
  Home page with upload functionality.
  """
  use ObservatoryWeb, :live_view

  alias ObservatoryWeb.FileUploadComponent

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:current_path, ~p"/")
     |> assign(:page_title, "Home")
     |> assign(:uploaded_file, nil)
     |> assign(:drag_active, false)
     |> allow_upload(:file,
       accept: ~w(.mp4 .mov .mkv .avi .webm),
       max_entries: 1,
       max_file_size: 500_000_000
     )}
  end

  @impl true
  def handle_event("analyze-media", _params, socket) do
    case consume_uploaded_entries(socket, :file, fn %{path: path}, entry ->
           {:ok, %{path: path, name: entry.client_name, size: entry.client_size}}
         end) do
      [%{path: path} = file_info] ->
        {:noreply,
         socket
         |> assign(:uploaded_file, file_info)
         |> push_navigate(to: ~p"/analyze?file=#{URI.encode_www_form(path)}")}

      _ ->
        {:noreply, put_flash(socket, :error, "No file uploaded")}
    end
  end

  @impl true
  def handle_event("analyze-gop", _params, socket) do
    case consume_uploaded_entries(socket, :file, fn %{path: path}, entry ->
           {:ok, %{path: path, name: entry.client_name, size: entry.client_size}}
         end) do
      [%{path: path} = file_info] ->
        {:noreply,
         socket
         |> assign(:uploaded_file, file_info)
         |> push_navigate(to: ~p"/gop?file=#{URI.encode_www_form(path)}")}

      _ ->
        {:noreply, put_flash(socket, :error, "No file uploaded")}
    end
  end

  @impl true
  def handle_event("drag-active", _params, socket) do
    {:noreply, assign(socket, :drag_active, true)}
  end

  @impl true
  def handle_event("drag-inactive", _params, socket) do
    {:noreply, assign(socket, :drag_active, false)}
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

      <!-- Upload Section -->
      <div class="max-w-2xl mx-auto">
        <div class="section-header text-center mb-8">
          <span class="section-title">UPLOAD VIDEO</span>
        </div>

        <.live_component
          module={FileUploadComponent}
          id="home-upload"
          uploads={@uploads}
          drag_active={@drag_active}
          action_label="START ANALYSIS"
          on_analyze="analyze-media"
        />
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
