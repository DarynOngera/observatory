defmodule ObservatoryWeb.AnalyzeLive do
  @moduledoc """
  Media analysis LiveView with terminal-styled output.
  """
  use ObservatoryWeb, :live_view

  alias Observatory.{Introspector, MediaSchema}

  @impl true
  def mount(params, _session, socket) do
    file_path = decode_file_param(params["file"])

    socket =
      socket
      |> assign(:current_path, ~p"/analyze")
      |> assign(:page_title, "Analyze")
      |> assign(:file_path, file_path)
      |> assign(:media_schema, nil)
      |> assign(:loading, false)
      |> assign(:error, nil)
      |> allow_upload(:file,
        accept: ~w(.mp4 .mov .mkv .avi .webm),
        max_entries: 1,
        max_file_size: 500_000_000
      )

    # Auto-analyze if file path provided
    socket =
      if file_path && File.exists?(file_path) do
        analyze_file(socket, file_path)
      else
        socket
      end

    {:ok, socket}
  end

  @impl true
  def handle_event("analyze", _params, socket) do
    case consume_uploaded_entries(socket, :file, fn %{path: path}, _entry ->
           {:ok, path}
         end) do
      [path] ->
        {:noreply, analyze_file(socket, path)}

      _ ->
        {:noreply, put_flash(socket, :error, "Please upload a file first")}
    end
  end

  @impl true
  def handle_event("clear", _params, socket) do
    {:noreply,
     socket
     |> assign(:media_schema, nil)
     |> assign(:file_path, nil)
     |> assign(:error, nil)}
  end

  defp analyze_file(socket, path) do
    socket
    |> assign(:loading, true)
    |> assign(:error, nil)
    |> start_async(:analysis, fn ->
      case Introspector.analyze(path) do
        {:ok, schema} -> {:ok, schema}
        {:error, reason} -> {:error, reason}
      end
    end)
  end

  @impl true
  def handle_async(:analysis, {:ok, {:ok, schema}}, socket) do
    {:noreply,
     socket
     |> assign(:loading, false)
     |> assign(:media_schema, schema)}
  end

  @impl true
  def handle_async(:analysis, {:ok, {:error, reason}}, socket) do
    {:noreply,
     socket
     |> assign(:loading, false)
     |> assign(:error, inspect(reason))}
  end

  @impl true
  def handle_async(:analysis, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> assign(:loading, false)
     |> assign(:error, "Analysis failed: #{inspect(reason)}")}
  end

  defp decode_file_param(nil), do: nil
  defp decode_file_param(path), do: URI.decode_www_form(path)

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-lg">
      <!-- Header -->
      <div class="flex justify-between mb-6">
        <div>
          <h2>MEDIA ANALYSIS</h2>
          <p class="font-mono text-sm text-secondary mt-1">
            Comprehensive codec and format inspection
          </p>
        </div>

        <%= if @media_schema do %>
          <button phx-click="clear" class="btn btn-secondary">
            NEW ANALYSIS
          </button>
        <% end %>
      </div>

      <!-- Upload Section (when no file analyzed) -->
      <%= if !@media_schema && !@loading do %>
        <div class="card p-8">
          <form phx-submit="analyze" phx-change="validate">
            <div class="upload-zone" phx-drop-target={@uploads.file.ref}>
              <.live_file_input upload={@uploads.file} class="hidden" />

              <div class="pointer-events-none">
                <div class="upload-icon">[F]</div>
                <p class="upload-text">
                  DROP VIDEO FILE TO ANALYZE
                </p>
                <p class="upload-subtext">
                  or click to browse
                </p>
              </div>
            </div>

            <%= for entry <- @uploads.file.entries do %>
              <div class="card mt-6 p-4 flex justify-between items-center">
                <div class="flex items-center gap-3">
                  <span class="text-green">[F]</span>
                  <span class="font-mono text-sm"><%= entry.client_name %></span>
                  <span class="text-xs text-gray">(<%= format_bytes(entry.client_size) %>)</span>
                </div>

                <button type="submit" class="btn" disabled={@loading}>
                  <%= if @loading, do: "ANALYZING...", else: "ANALYZE" %>
                </button>
              </div>
            <% end %>
          </form>
        </div>
      <% end %>

      <!-- Loading State -->
      <%= if @loading do %>
        <div class="card p-8 text-center">
          <div class="inline-block mb-4">
            <div class="animate-spin w-12 h-12 border-2 border-green border-t-transparent rounded-full"></div>
          </div>
          <p class="font-mono text-sm text-secondary animate-pulse">ANALYZING MEDIA FILE...</p>
          <p class="font-mono text-xs text-gray mt-2">Running ffprobe analysis</p>
        </div>
      <% end %>

      <!-- Error State -->
      <%= if @error do %>
        <div class="flash flash-error">
          <div class="flex items-center gap-2 mb-2">
            <span class="text-red font-bold">[X]</span>
            <span class="font-mono text-sm text-red font-semibold">ANALYSIS ERROR</span>
          </div>
          <p class="font-mono text-xs"><%= @error %></p>
        </div>
      <% end %>

      <!-- Results -->
      <%= if @media_schema do %>
        <div class="space-y-lg">
          <!-- File Info -->
          <div class="card p-6">
            <div class="section-header">
              <span class="section-title">FILE INFORMATION</span>
            </div>

            <div class="grid grid-cols-4 gap-4">
              <div class="card p-4">
                <div class="text-xs text-gray mb-1">FILENAME</div>
                <div class="font-mono text-sm truncate">
                  <%= Path.basename(@media_schema.file_path) %>
                </div>
              </div>

              <div class="card p-4">
                <div class="text-xs text-gray mb-1">DURATION</div>
                <div class="text-green font-mono text-sm">
                  <%= format_duration(@media_schema.format.duration_sec) %>
                </div>
              </div>

              <div class="card p-4">
                <div class="text-xs text-gray mb-1">FILE SIZE</div>
                <div class="text-green font-mono text-sm">
                  <%= format_bytes(@media_schema.format.size_bytes) %>
                </div>
              </div>

              <div class="card p-4">
                <div class="text-xs text-gray mb-1">BITRATE</div>
                <div class="text-green font-mono text-sm">
                  <%= format_bitrate(@media_schema.format.bitrate_bps) %>
                </div>
              </div>
            </div>

            <div class="card p-4 mt-4">
              <div class="text-xs text-gray mb-1">CONTAINER FORMAT</div>
              <div class="font-mono text-sm">
                <%= @media_schema.format.container_type %>
              </div>
            </div>
          </div>

          <!-- Streams -->
          <div class="card p-6">
            <div class="section-header">
              <span class="section-title">STREAMS (<%= length(@media_schema.streams) %>)</span>
            </div>

            <div class="space-y">
              <%= for stream <- @media_schema.streams do %>
                <div class="card p-4">
                  <div class="flex items-center gap-3 mb-3">
                    <span class={stream_type_badge(stream.type)}>
                      <%= String.upcase(to_string(stream.type)) %>
                    </span>
                    <span class="font-mono text-sm">
                      <%= stream.codec_name %>
                    </span>
                    <%= if stream.codec_profile do %>
                      <span class="font-mono text-xs text-gray">
                        <%= stream.codec_profile %>
                      </span>
                    <% end %>
                  </div>

                  <div class="grid grid-cols-4 gap-4 font-mono text-xs">
                    <%= if stream.type == :video do %>
                      <div>
                        <span class="text-gray">RESOLUTION:</span>
                        <span>
                          <%= MediaSchema.Stream.resolution(stream) || "N/A" %>
                        </span>
                      </div>
                      <div>
                        <span class="text-gray">FRAMERATE:</span>
                        <span>
                          <%= format_framerate(stream.frame_rate) %>
                        </span>
                      </div>
                      <div>
                        <span class="text-gray">PIXEL:</span>
                        <span>
                          <%= stream.pixel_format || "N/A" %>
                        </span>
                      </div>
                    <% end %>

                    <%= if stream.type == :audio do %>
                      <div>
                        <span class="text-gray">SAMPLE RATE:</span>
                        <span>
                          <%= format_sample_rate(stream.sample_rate) %>
                        </span>
                      </div>
                      <div>
                        <span class="text-gray">CHANNELS:</span>
                        <span>
                          <%= stream.channels || "N/A" %>
                        </span>
                      </div>
                    <% end %>

                    <div>
                      <span class="text-gray">BITRATE:</span>
                      <span>
                        <%= format_bitrate(stream.bitrate_bps) %>
                      </span>
                    </div>

                    <div>
                      <span class="text-gray">DURATION:</span>
                      <span>
                        <%= format_duration(stream.duration_sec) %>
                      </span>
                    </div>
                  </div>
                </div>
              <% end %>
            </div>
          </div>

          <!-- Raw Data Toggle -->
          <div class="card p-6">
            <details>
              <summary class="flex items-center gap-2 cursor-pointer list-none">
                <span class="font-mono text-sm text-secondary hover:text-green transition-all">
                  > SHOW RAW SCHEMA DATA
                </span>
                <span class="font-mono text-xs text-gray">[+]</span>
              </summary>
              <div class="mt-4 terminal-output">
                <pre class="font-mono text-xs text-gray m-0"><%= inspect(@media_schema, pretty: true) %></pre>
              </div>
            </details>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  defp format_bytes(nil), do: "N/A"
  defp format_bytes(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_bytes(bytes) when bytes < 1024 * 1024, do: "#{Float.round(bytes / 1024, 1)} KB"
  defp format_bytes(bytes), do: "#{Float.round(bytes / 1024 / 1024, 2)} MB"

  defp format_bitrate(nil), do: "N/A"
  defp format_bitrate(bps), do: "#{Float.round(bps / 1000, 0)} kbps"

  defp format_duration(nil), do: "N/A"

  defp format_duration(seconds) do
    minutes = trunc(seconds / 60)
    secs = trunc(rem(trunc(seconds), 60))
    ms = trunc((seconds - trunc(seconds)) * 1000)
    "#{minutes}:#{String.pad_leading("#{secs}", 2, "0")}.#{ms}"
  end

  defp format_framerate(nil), do: "N/A"
  defp format_framerate({num, den}), do: "#{Float.round(num / den, 2)} fps"

  defp format_sample_rate(nil), do: "N/A"
  defp format_sample_rate(rate), do: "#{trunc(rate / 1000)} kHz"

  defp stream_type_badge(:video), do: "badge-video"
  defp stream_type_badge(:audio), do: "badge-audio"
  defp stream_type_badge(_), do: "badge-other"
end
