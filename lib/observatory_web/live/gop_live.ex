defmodule ObservatoryWeb.GopLive do
  @moduledoc """
  GOP analysis LiveView with terminal-styled output and proper file upload handling.
  """
  use ObservatoryWeb, :live_view

  alias Observatory.GOPAnalyzer
  require Logger

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
        accept: :any,
        max_entries: 1,
        max_file_size: 500_000_000,
        auto_upload: true,
        progress: &handle_progress/3
      )

    # Auto-analyze if file path provided
    socket =
      if file_path && File.exists?(file_path) do
        Logger.info("Auto-analyzing GOP for file: #{file_path}")
        analyze_file(socket, file_path)
      else
        if file_path do
          Logger.warning("GOP: File path provided but does not exist: #{file_path}")
          put_flash(socket, :error, "File not found: #{file_path}")
        else
          socket
        end
      end

    {:ok, socket}
  end

  @impl true
  def handle_event("validate", params, socket) do
    Logger.debug("GOP: File upload validation triggered: #{inspect(params)}")

    # Check for upload errors
    socket =
      Enum.reduce(socket.assigns.uploads.file.entries, socket, fn entry, acc_socket ->
        errors = upload_errors(socket.assigns.uploads.file, entry)

        Enum.reduce(errors, acc_socket, fn error, s ->
          Logger.warning("GOP: Upload validation error: #{inspect(error)}")
          put_flash(s, :error, error_to_string(error))
        end)
      end)

    {:noreply, socket}
  end

  @impl true
  def handle_event("analyze", _params, socket) do
    Logger.info("GOP: Analyze button clicked")

    uploaded_files =
      consume_uploaded_entries(socket, :file, fn %{path: path}, entry ->
        Logger.info("GOP: Processing upload: #{entry.client_name}")

        # Create persistent copy
        dest = Path.join([System.tmp_dir!(), "observatory", entry.client_name])
        File.mkdir_p!(Path.dirname(dest))

        case File.cp(path, dest) do
          :ok ->
            Logger.info("GOP: File copied to: #{dest}")
            {:ok, dest}

          {:error, reason} ->
            Logger.error("GOP: Failed to copy file: #{inspect(reason)}")
            {:postpone, reason}
        end
      end)

    case uploaded_files do
      [file_path] when is_binary(file_path) ->
        Logger.info("GOP: Starting analysis for: #{file_path}")
        {:noreply, analyze_file(socket, file_path)}

      [] ->
        Logger.warning("GOP: No files were consumed")
        {:noreply, put_flash(socket, :error, "Please upload a file first")}

      error ->
        Logger.error("GOP: Upload consumption failed: #{inspect(error)}")
        {:noreply, put_flash(socket, :error, "Failed to process upload")}
    end
  end

  @impl true
  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    Logger.info("GOP: Canceling upload: #{ref}")
    {:noreply, cancel_upload(socket, :file, ref)}
  end

  @impl true
  def handle_event("clear", _params, socket) do
    Logger.info("GOP: Clearing analysis")

    {:noreply,
     socket
     |> assign(:gop_stats, nil)
     |> assign(:file_path, nil)
     |> assign(:error, nil)}
  end

  defp handle_progress(:file, entry, socket) do
    Logger.debug("GOP: Upload progress: #{entry.client_name} - #{entry.progress}%")

    if entry.done? do
      Logger.info("GOP: Upload complete: #{entry.client_name}")
    end

    {:noreply, socket}
  end

  defp analyze_file(socket, path) do
    Logger.info("GOP: Starting file analysis: #{path}")
    Logger.info("GOP: File exists? #{File.exists?(path)}")

    socket
    |> assign(:loading, true)
    |> assign(:error, nil)
    |> assign(:file_path, path)
    |> start_async(:analysis, fn ->
      Logger.info("GOP: Async analysis started for: #{path}")

      result =
        case GOPAnalyzer.analyze(path) do
          {:ok, stats} ->
            Logger.info("GOP: Analysis successful!")
            {:ok, stats}

          {:error, reason} = error ->
            Logger.error("GOP: Analysis failed: #{inspect(reason)}")
            error
        end

      result
    end)
  end

  @impl true
  def handle_async(:analysis, {:ok, {:ok, stats}}, socket) do
    Logger.info("GOP: Analysis completed successfully")

    {:noreply,
     socket
     |> assign(:loading, false)
     |> assign(:gop_stats, stats)
     |> put_flash(:info, "GOP analysis completed")}
  end

  @impl true
  def handle_async(:analysis, {:ok, {:error, reason}}, socket) do
    Logger.error("GOP: Analysis failed: #{inspect(reason)}")

    error_msg =
      case reason do
        :file_not_found -> "File not found"
        {:ffprobe_failed, output} -> "FFprobe failed: #{String.slice(output, 0, 200)}"
        {:ffprobe_not_found, _} -> "FFprobe not found. Install FFmpeg."
        :no_frames -> "No frames found in video"
        other -> "GOP analysis error: #{inspect(other)}"
      end

    {:noreply,
     socket
     |> assign(:loading, false)
     |> assign(:error, error_msg)
     |> put_flash(:error, error_msg)}
  end

  @impl true
  def handle_async(:analysis, {:exit, reason}, socket) do
    Logger.error("GOP: Analysis process exited: #{inspect(reason)}")

    {:noreply,
     socket
     |> assign(:loading, false)
     |> assign(:error, "Analysis failed: #{inspect(reason)}")
     |> put_flash(:error, "GOP analysis process failed")}
  end

  defp decode_file_param(nil), do: nil

  defp decode_file_param(path) when is_binary(path) do
    decoded = URI.decode_www_form(path)

    if File.exists?(decoded) do
      decoded
    else
      Logger.warning("GOP: Decoded file does not exist: #{decoded}")
      nil
    end
  end

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
          <form id="upload-form" phx-submit="analyze" phx-change="validate">
            <.live_file_input upload={@uploads.file} class="hidden" />
            
            <%= if @uploads.file.entries == [] do %>
              <label 
                for={@uploads.file.ref}
                class="upload-zone" 
                phx-drop-target={@uploads.file.ref}
              >
                <div>
                  <div class="upload-icon">[G]</div>
                  <p class="upload-text">
                    DROP VIDEO FILE FOR GOP ANALYSIS
                  </p>
                  <p class="upload-subtext">
                    or click to browse
                  </p>
                </div>
              </label>
            <% else %>
              <%= for entry <- @uploads.file.entries do %>
                <div class="card mt-6 p-4">
                  <div class="flex justify-between items-center mb-3">
                    <div class="flex items-center gap-3">
                      <span class="text-green">[F]</span>
                      <span class="font-mono text-sm"><%= entry.client_name %></span>
                      <span class="text-xs text-gray">(<%= format_bytes(entry.client_size) %>)</span>
                    </div>

                    <button
                      type="button"
                      phx-click="cancel-upload"
                      phx-value-ref={entry.ref}
                      class="btn btn-secondary"
                      style="padding: 4px 8px; font-size: 12px;"
                    >
                      ✕
                    </button>
                  </div>
                  
                  <%= if entry.progress < 100 do %>
                    <div class="flex items-center gap-3">
                      <div class="w-full">
                        <div class="border" style="height: 8px; overflow: hidden;">
                          <div
                            class="bg-green h-full transition-all"
                            style={"width: #{entry.progress}%;"}
                          >
                          </div>
                        </div>
                      </div>
                      <span class="font-mono text-xs text-green w-16 text-right">
                        <%= entry.progress %>%
                      </span>
                    </div>
                  <% end %>

                  <%= for err <- upload_errors(@uploads.file, entry) do %>
                    <div class="flash flash-error mt-4">
                      <span class="font-bold">[ERROR]</span>
                      <%= error_to_string(err) %>
                    </div>
                  <% end %>
                </div>
              <% end %>
              
              <!-- Always show analyze button when entries exist -->
              <div class="mt-6 text-center">
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
            <span class="font-mono text-sm text-red font-semibold">ANALYSIS ERROR</span>
          </div>
          <p class="font-mono text-xs"><%= @error %></p>
        </div>
      <% end %>

      <!-- Results -->
      <%= if @gop_stats do %>
        <div class="space-y-lg">
          <!-- Summary Stats -->
          <div class="card p-6">
            <div class="section-header">
              <span class="section-title">GOP STATISTICS</span>
            </div>

            <div class="grid grid-cols-4 gap-4">
              <div class="card p-4">
                <div class="text-xs text-gray mb-1">TOTAL GOPS</div>
                <div class="text-green font-mono text-2xl font-bold">
                  <%= @gop_stats.stats.total_gops %>
                </div>
              </div>

              <div class="card p-4">
                <div class="text-xs text-gray mb-1">AVG GOP SIZE</div>
                <div class="text-green font-mono text-2xl font-bold">
                  <%= Float.round(@gop_stats.stats.avg_gop_size, 1) %> frames
                </div>
              </div>

              <div class="card p-4">
                <div class="text-xs text-gray mb-1">AVG GOP DURATION</div>
                <div class="text-green font-mono text-2xl font-bold">
                  <%= Float.round(@gop_stats.stats.avg_gop_duration_sec, 2) %>s
                </div>
              </div>

              <div class="card p-4">
                <div class="text-xs text-gray mb-1">SEEKABILITY SCORE</div>
                <div class="text-green font-mono text-2xl font-bold">
                  <%= Float.round(@gop_stats.stats.seekability_score, 1) %>/100
                </div>
              </div>
            </div>
          </div>

          <!-- Frame Distribution -->
          <div class="card p-6">
            <div class="section-header">
              <span class="section-title">FRAME DISTRIBUTION</span>
            </div>

            <div class="grid grid-cols-3 gap-4">
              <div class="card p-4 text-center">
                <div class="text-xs text-gray mb-2">I-FRAMES (KEY)</div>
                <div class="text-green font-mono text-3xl font-bold">
                  <%= @gop_stats.stats.i_frame_ratio |> Float.round(1) %>%
                </div>
                <div class="text-xs text-gray mt-1">
                  <%= @gop_stats.total_frames %> total frames
                </div>
              </div>

              <div class="card p-4 text-center">
                <div class="text-xs text-gray mb-2">P-FRAMES</div>
                <div class="text-blue font-mono text-3xl font-bold">
                  <%= (100 - @gop_stats.stats.i_frame_ratio - @gop_stats.stats.b_frame_ratio) |> Float.round(1) %>%
                </div>
              </div>

              <div class="card p-4 text-center">
                <div class="text-xs text-gray mb-2">B-FRAMES</div>
                <div class="text-yellow font-mono text-3xl font-bold">
                  <%= @gop_stats.stats.b_frame_ratio |> Float.round(1) %>%
                </div>
              </div>
            </div>
          </div>

          <!-- GOP List -->
          <div class="card p-6">
            <div class="section-header">
              <span class="section-title">GOP BREAKDOWN (<%= length(@gop_stats.gops) %>)</span>
            </div>

            <div class="space-y">
              <%= for {gop, index} <- Enum.with_index(@gop_stats.gops) do %>
                <div class="card p-4">
                  <div class="flex items-center justify-between mb-3">
                    <div class="flex items-center gap-4">
                      <span class="text-green font-mono font-bold">GOP #<%= index + 1 %></span>
                      <span class="badge-video"><%= gop.frame_count %> FRAMES</span>
                    </div>
                    <div class="text-xs text-gray font-mono">
                      <%= gop.start_pts_sec |> Float.round(3) %>s - <%= gop.end_pts_sec |> Float.round(3) %>s
                    </div>
                  </div>

                  <div class="grid grid-cols-4 gap-4 font-mono text-xs">
                    <div>
                      <span class="text-gray">DURATION:</span>
                      <span class="text-green"><%= Float.round(gop.duration_sec, 3) %>s</span>
                    </div>
                    <div>
                      <span class="text-gray">I-FRAME SIZE:</span>
                      <span class="text-green"><%= format_bytes(gop.i_frame_bytes) %></span>
                    </div>
                    <div>
                      <span class="text-gray">TOTAL SIZE:</span>
                      <span class="text-green"><%= format_bytes(gop.total_bytes) %></span>
                    </div>
                    <div>
                      <span class="text-gray">COMPRESSION:</span>
                      <span class="text-green">
                        <%= if gop.compression_ratio, do: "#{Float.round(gop.compression_ratio, 1)}:1", else: "N/A" %>
                      </span>
                    </div>
                  </div>

                  <div class="mt-3 pt-3 border-t">
                    <div class="text-xs text-gray mb-2">STRUCTURE:</div>
                    <div class="font-mono text-xs break-all">
                      <%= gop.structure |> Enum.take(20) |> Enum.join(" ") %>
                      <%= if length(gop.structure) > 20, do: " ...", else: "" %>
                    </div>
                  </div>
                </div>
              <% end %>
            </div>
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

  defp error_to_string(:too_large), do: "FILE TOO LARGE (max 500MB)"
  defp error_to_string(:too_many_files), do: "TOO MANY FILES (max 1)"
  defp error_to_string(:not_accepted), do: "FILE TYPE NOT ACCEPTED"
  defp error_to_string(err), do: "ERROR: #{inspect(err)}"
end
