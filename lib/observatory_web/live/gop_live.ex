defmodule ObservatoryWeb.GopLive do
  @moduledoc """
  GOP analysis LiveView with terminal-styled output.
  """
  use ObservatoryWeb, :live_view

  alias Observatory.GOPAnalyzer

  @impl true
  def mount(params, _session, socket) do
    file_path = decode_file_param(params["file"])

    socket =
      socket
      |> assign(:current_path, ~p"/gop")
      |> assign(:page_title, "GOP Analysis")
      |> assign(:file_path, file_path)
      |> assign(:gop_stats, nil)
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
     |> assign(:gop_stats, nil)
     |> assign(:file_path, nil)
     |> assign(:error, nil)}
  end

  defp analyze_file(socket, path) do
    socket
    |> assign(:loading, true)
    |> assign(:error, nil)
    |> start_async(:analysis, fn ->
      case GOPAnalyzer.analyze(path) do
        {:ok, stats} -> {:ok, stats}
        {:error, reason} -> {:error, reason}
      end
    end)
  end

  @impl true
  def handle_async(:analysis, {:ok, {:ok, stats}}, socket) do
    {:noreply,
     socket
     |> assign(:loading, false)
     |> assign(:gop_stats, stats)}
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
     |> assign(:error, "GOP Analysis failed: #{inspect(reason)}")}
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
          <h2>GOP ANALYSIS</h2>
          <p class="font-mono text-sm text-secondary mt-1">
            Group of Pictures structure inspection
          </p>
        </div>

        <%= if @gop_stats do %>
          <button phx-click="clear" class="btn btn-secondary">
            NEW ANALYSIS
          </button>
        <% end %>
      </div>

      <!-- Upload Section (when no file analyzed) -->
      <%= if !@gop_stats && !@loading do %>
        <div class="card p-8">
          <form phx-submit="analyze" phx-change="validate">
            <div class="upload-zone" phx-drop-target={@uploads.file.ref}>
              <.live_file_input upload={@uploads.file} class="hidden" />

              <div class="pointer-events-none">
                <div class="upload-icon">[G]</div>
                <p class="upload-text">
                  DROP VIDEO FOR GOP ANALYSIS
                </p>
                <p class="upload-subtext">
                  Analyze I/P/B frame structure
                </p>
              </div>
            </div>

            <%= for entry <- @uploads.file.entries do %>
              <div class="card mt-6 p-4 flex justify-between items-center">
                <div class="flex items-center gap-3">
                  <span class="text-green">[G]</span>
                  <span class="font-mono text-sm"><%= entry.client_name %></span>
                  <span class="text-xs text-gray">(<%= format_bytes(entry.client_size) %>)</span>
                </div>

                <button type="submit" class="btn" disabled={@loading}>
                  <%= if @loading, do: "ANALYZING...", else: "ANALYZE GOP" %>
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
          <p class="font-mono text-sm text-secondary animate-pulse">ANALYZING GOP STRUCTURE...</p>
          <p class="font-mono text-xs text-gray mt-2">Processing frame data</p>
        </div>
      <% end %>

      <!-- Error State -->
      <%= if @error do %>
        <div class="flash flash-error">
          <div class="flex items-center gap-2 mb-2">
            <span class="text-red font-bold">[X]</span>
            <span class="font-mono text-sm text-red font-semibold">GOP ANALYSIS ERROR</span>
          </div>
          <p class="font-mono text-xs"><%= @error %></p>
        </div>
      <% end %>

      <%!-- Results --%>
      <%= if @gop_stats do %>
        <div style="display: flex; flex-direction: column; gap: 24px;">
          <%!-- Summary Stats --%>
          <div style="background: #111111; border: 1px solid #2a2a2a; border-radius: 8px; padding: 24px; transition: border-color 0.2s ease;">
            <div style="border-bottom: 1px solid #2a2a2a; padding-bottom: 8px; margin-bottom: 24px;">
              <span style="color: #00ff88; font-weight: 600; text-transform: uppercase; letter-spacing: 0.1em; font-size: 12px; font-family: 'JetBrains Mono', monospace;">GOP STATISTICS</span>
            </div>

            <div style="display: grid; grid-template-columns: repeat(4, 1fr); gap: 16px;">
              <div style="padding: 16px;" style="background: #111111; border-radius: 4px; border: 1px solid #2a2a2a;">
                <div style="font-size: 12px; color: #555555; font-family: 'JetBrains Mono', monospace; margin-bottom: 4px;">TOTAL FRAMES</div>
                <div style="font-size: 24px; color: #00ff88; font-family: 'JetBrains Mono', monospace; font-weight: 700;" style="font-weight: 700;">
                  <%= @gop_stats.total_frames %>
                </div>
              </div>

              <div style="padding: 16px;" style="background: #111111; border-radius: 4px; border: 1px solid #2a2a2a;">
                <div style="font-size: 12px; color: #555555; font-family: 'JetBrains Mono', monospace; margin-bottom: 4px;">TOTAL GOPS</div>
                <div style="font-size: 24px; color: #00ff88; font-family: 'JetBrains Mono', monospace; font-weight: 700;" style="font-weight: 700;">
                  <%= @gop_stats.stats.total_gops %>
                </div>
              </div>

              <div style="padding: 16px;" style="background: #111111; border-radius: 4px; border: 1px solid #2a2a2a;">
                <div style="font-size: 12px; color: #555555; font-family: 'JetBrains Mono', monospace; margin-bottom: 4px;">AVG GOP SIZE</div>
                <div style="font-size: 24px; color: #00ff88; font-family: 'JetBrains Mono', monospace; font-weight: 700;" style="font-weight: 700;">
                  <%= Float.round(@gop_stats.stats.avg_gop_size, 1) %>
                </div>
                <div style="font-size: 12px; color: #555555; font-family: 'JetBrains Mono', monospace;">frames</div>
              </div>

              <div style="padding: 16px;" style="background: #111111; border-radius: 4px; border: 1px solid #2a2a2a;">
                <div style="font-size: 12px; color: #555555; font-family: 'JetBrains Mono', monospace; margin-bottom: 4px;">SEEKABILITY</div>
                <div style="font-size: 24px; color: #00ff88; font-family: 'JetBrains Mono', monospace; font-weight: 700;" style="font-weight: 700;">
                  <%= Float.round(@gop_stats.stats.seekability_score, 1) %>
                </div>
                <div style="font-size: 12px; color: #555555; font-family: 'JetBrains Mono', monospace;">/100</div>
              </div>
            </div>

            <div style="display: grid; grid-template-columns: repeat(4, 1fr); gap: 16px; margin-top: 16px;">
              <div style="padding: 16px;" style="background: #111111; border-radius: 4px; border: 1px solid #2a2a2a;">
                <div style="font-size: 12px; color: #555555; font-family: 'JetBrains Mono', monospace; margin-bottom: 4px;">MIN GOP</div>
                <div style="font-size: 18px; font-family: 'JetBrains Mono', monospace;" style="color: #e0e0e0;">
                  <%= @gop_stats.stats.min_gop_size %> frames
                </div>
              </div>

              <div style="padding: 16px;" style="background: #111111; border-radius: 4px; border: 1px solid #2a2a2a;">
                <div style="font-size: 12px; color: #555555; font-family: 'JetBrains Mono', monospace; margin-bottom: 4px;">MAX GOP</div>
                <div style="font-size: 18px; font-family: 'JetBrains Mono', monospace;" style="color: #e0e0e0;">
                  <%= @gop_stats.stats.max_gop_size %> frames
                </div>
              </div>

              <div style="padding: 16px;" style="background: #111111; border-radius: 4px; border: 1px solid #2a2a2a;">
                <div style="font-size: 12px; color: #555555; font-family: 'JetBrains Mono', monospace; margin-bottom: 4px;">RESOLUTION</div>
                <div style="font-size: 18px; font-family: 'JetBrains Mono', monospace;" style="color: #e0e0e0;">
                  <%= format_dimensions(@gop_stats.width, @gop_stats.height) %>
                </div>
              </div>

              <div style="padding: 16px;" style="background: #111111; border-radius: 4px; border: 1px solid #2a2a2a;">
                <div style="font-size: 12px; color: #555555; font-family: 'JetBrains Mono', monospace; margin-bottom: 4px;">PIXEL FORMAT</div>
                <div style="font-size: 18px; font-family: 'JetBrains Mono', monospace;" style="color: #e0e0e0;">
                  <%= @gop_stats.pixel_format || "N/A" %>
                </div>
              </div>
            </div>
          </div>

          <%!-- GOP Distribution Chart --%>
          <%= if length(@gop_stats.gops) > 0 do %>
            <div style="background: #111111; border: 1px solid #2a2a2a; border-radius: 8px; padding: 24px; transition: border-color 0.2s ease;">
              <div style="border-bottom: 1px solid #2a2a2a; padding-bottom: 8px; margin-bottom: 24px;">
                <span style="color: #00ff88; font-weight: 600; text-transform: uppercase; letter-spacing: 0.1em; font-size: 12px; font-family: 'JetBrains Mono', monospace;">GOP DISTRIBUTION</span>
              </div>

              <div style="display: flex; flex-direction: column; gap: 24px;">
                <%= for {gop, index} <- Enum.take(@gop_stats.gops, 50) |> Enum.with_index() do %>
                  <div style="display: flex; align-items: center; gap: 12px; font-size: 12px; font-family: 'JetBrains Mono', monospace;">
                    <span style="color: #555555;" style="width: 32px; text-align: right;"><%= index + 1 %></span>
                    <div style="flex: 1; background: #1a1a1a; border-radius: 2px; overflow: hidden; position: relative; height: 24px;">
                      <div
                        style={"height: 100%; background: #00ff88; transition: width 0.5s ease; width: #{gop_size_percentage(gop.size, @gop_stats.stats.max_gop_size)}%; box-shadow: 0 0 10px rgba(0, 255, 136, 0.3);"}
                      >
                      </div>
                      <span style="position: absolute; inset: 0; display: flex; align-items: center; padding: 0 8px; color: #e0e0e0;">
                        <%= if gop.idr? do %>
                          <span style="color: #00ff88; margin-right: 8px;">[IDR]</span>
                        <% end %>
                        <%= gop.size %> frames
                      </span>
                    </div>
                    <span style="color: #888888;" style="width: 80px; text-align: right;">
                      @<%= gop.start_pts %>
                    </span>
                  </div>
                <% end %>

                <%= if length(@gop_stats.gops) > 50 do %>
                  <div style="text-align: center; padding: 16px 0; font-size: 14px; color: #555555; font-family: 'JetBrains Mono', monospace;">
                    ... and <%= length(@gop_stats.gops) - 50 %> more GOPs
                  </div>
                <% end %>
              </div>
            </div>
          <% end %>

          <%!-- Frame Type Breakdown --%>
          <%= if length(@gop_stats.gops) > 0 do %>
            <div style="background: #111111; border: 1px solid #2a2a2a; border-radius: 8px; padding: 24px; transition: border-color 0.2s ease;">
              <div style="border-bottom: 1px solid #2a2a2a; padding-bottom: 8px; margin-bottom: 24px;">
                <span style="color: #00ff88; font-weight: 600; text-transform: uppercase; letter-spacing: 0.1em; font-size: 12px; font-family: 'JetBrains Mono', monospace;">FRAME TYPE ANALYSIS</span>
              </div>

              <% frame_counts = count_frame_types(@gop_stats.gops) %>

              <div style="display: grid; grid-template-columns: repeat(3, 1fr); gap: 16px; margin-bottom: 24px;">
                <div style="padding: 16px;" style="background: #111111; border-radius: 4px; border: 1px solid #2a2a2a; text-align: center;">
                  <div style="font-size: 12px; color: #555555; font-family: 'JetBrains Mono', monospace; margin-bottom: 8px;">I-FRAMES (IDR)</div>
                  <div style="font-size: 30px; color: #00ff88; font-family: 'JetBrains Mono', monospace; font-weight: 700;" style="font-weight: 700;">
                    <%= frame_counts.i_frames %>
                  </div>
                  <div style="font-size: 12px; color: #00ff88; font-family: 'JetBrains Mono', monospace; margin-top: 4px;">key frames</div>
                </div>

                <div style="padding: 16px;" style="background: #111111; border-radius: 4px; border: 1px solid #2a2a2a; text-align: center;">
                  <div style="font-size: 12px; color: #555555; font-family: 'JetBrains Mono', monospace; margin-bottom: 8px;">P-FRAMES</div>
                  <div style="font-size: 30px; font-family: 'JetBrains Mono', monospace; font-weight: 700;" style="font-weight: 700; color: #4488ff;">
                    <%= frame_counts.p_frames %>
                  </div>
                  <div style="font-size: 12px; font-family: 'JetBrains Mono', monospace; margin-top: 4px;" style="color: #4488ff;">predicted</div>
                </div>

                <div style="padding: 16px;" style="background: #111111; border-radius: 4px; border: 1px solid #2a2a2a; text-align: center;">
                  <div style="font-size: 12px; color: #555555; font-family: 'JetBrains Mono', monospace; margin-bottom: 8px;">B-FRAMES</div>
                  <div style="font-size: 30px; font-family: 'JetBrains Mono', monospace; font-weight: 700;" style="font-weight: 700; color: #ffaa00;">
                    <%= frame_counts.b_frames %>
                  </div>
                  <div style="font-size: 12px; font-family: 'JetBrains Mono', monospace; margin-top: 4px;" style="color: #ffaa00;">bi-directional</div>
                </div>
              </div>

              <div style="padding: 16px;" style="background: #111111; border-radius: 4px; border: 1px solid #2a2a2a;">
                <div style="display: flex; align-items: center; justify-content: space-between; font-size: 14px; font-family: 'JetBrains Mono', monospace;">
                  <span style="color: #888888;">Total Frames Processed:</span>
                  <span style="color: #e0e0e0;"><%= frame_counts.i_frames + frame_counts.p_frames + frame_counts.b_frames %></span>
                </div>
              </div>
            </div>
          <% end %>

          <%!-- Raw Data Toggle --%>
          <div style="background: #111111; border: 1px solid #2a2a2a; border-radius: 8px; padding: 24px; transition: border-color 0.2s ease;">
            <details>
              <summary style="display: flex; align-items: center; gap: 8px; cursor: pointer; list-style: none;">
                <span style="font-size: 14px; color: #888888; font-family: 'JetBrains Mono', monospace;" style="transition: color 0.2s ease;" onmouseover="this.style.color='#00ff88'" onmouseout="this.style.color='#888888'">
                  > SHOW RAW GOP DATA
                </span>
                <span style="font-size: 12px; color: #555555; font-family: 'JetBrains Mono', monospace;">[+]</span>
              </summary>
              <div style="margin-top: 16px; background: #111111; border-left: 3px solid #00ff88; padding: 16px; font-family: 'JetBrains Mono', monospace; font-size: 14px; line-height: 1.6;" style="border-radius: 4px; overflow-x: auto;">
                <pre style="font-size: 12px; color: #888888; margin: 0;"><%= inspect(@gop_stats, pretty: true, limit: 100) %></pre>
              </div>
            </details>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  defp format_bytes(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_bytes(bytes) when bytes < 1024 * 1024, do: "#{Float.round(bytes / 1024, 1)} KB"
  defp format_bytes(bytes), do: "#{Float.round(bytes / 1024 / 1024, 2)} MB"

  defp format_dimensions(nil, nil), do: "N/A"
  defp format_dimensions(w, h), do: "#{w}x#{h}"

  defp gop_size_percentage(size, max) when max > 0 do
    Float.round(size / max * 100, 1)
  end

  defp gop_size_percentage(_, _), do: 0

  defp count_frame_types(gops) do
    Enum.reduce(gops, %{i_frames: 0, p_frames: 0, b_frames: 0}, fn gop, acc ->
      %{
        i_frames: acc.i_frames + (gop.i_frames || 0),
        p_frames: acc.p_frames + (gop.p_frames || 0),
        b_frames: acc.b_frames + (gop.b_frames || 0)
      }
    end)
  end
end
