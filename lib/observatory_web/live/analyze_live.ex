defmodule ObservatoryWeb.AnalyzeLive do
  @moduledoc """
  Media analysis LiveView with terminal-styled output and proper file upload handling.
  """
  use ObservatoryWeb, :live_view

  alias Observatory.{Introspector, MediaSchema}
  require Logger

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
        accept: :any,
        max_entries: 1,
        max_file_size: 500_000_000,
        auto_upload: true,
        progress: &handle_progress/3
      )

    # Auto-analyze if file path provided
    socket =
      if file_path && File.exists?(file_path) do
        Logger.info("Auto-analyzing file: #{file_path}")
        analyze_file(socket, file_path)
      else
        if file_path do
          Logger.warning("File path provided but does not exist: #{file_path}")
          put_flash(socket, :error, "File not found: #{file_path}")
        else
          socket
        end
      end

    {:ok, socket}
  end

  @impl true
  def handle_event("validate", params, socket) do
    Logger.info("VALIDATE EVENT TRIGGERED")
    Logger.info("Params: #{inspect(params, pretty: true, limit: 10)}")
    Logger.info("Entry count: #{length(socket.assigns.uploads.file.entries)}")

    # Log each entry
    Enum.each(socket.assigns.uploads.file.entries, fn entry ->
      Logger.info(
        "Entry: #{entry.client_name}, progress: #{entry.progress}, done: #{entry.done?}"
      )
    end)

    # Check for upload errors
    socket =
      Enum.reduce(socket.assigns.uploads.file.entries, socket, fn entry, acc_socket ->
        errors = upload_errors(socket.assigns.uploads.file, entry)

        Enum.reduce(errors, acc_socket, fn error, s ->
          Logger.warning("Upload validation error: #{inspect(error)}")
          put_flash(s, :error, error_to_string(error))
        end)
      end)

    {:noreply, socket}
  end

  @impl true
  def handle_event("analyze", _params, socket) do
    Logger.info("Analyze button clicked")
    Logger.info("Current entries: #{length(socket.assigns.uploads.file.entries)}")

    # Log each entry's state
    Enum.each(socket.assigns.uploads.file.entries, fn entry ->
      Logger.info(
        "Entry: #{entry.client_name}, progress: #{entry.progress}%, done?: #{entry.done?}"
      )
    end)

    uploaded_files =
      consume_uploaded_entries(socket, :file, fn %{path: path}, entry ->
        Logger.info("Processing upload: #{entry.client_name} from temp path: #{path}")
        Logger.info("File exists at temp path? #{File.exists?(path)}")

        # Create persistent copy
        dest = Path.join([System.tmp_dir!(), "observatory", entry.client_name])
        File.mkdir_p!(Path.dirname(dest))

        case File.cp(path, dest) do
          :ok ->
            Logger.info("File copied to: #{dest}")
            {:ok, dest}

          {:error, reason} ->
            Logger.error("Failed to copy file: #{inspect(reason)}")
            {:postpone, reason}
        end
      end)

    Logger.info("Uploaded files result: #{inspect(uploaded_files)}")

    case uploaded_files do
      [file_path] when is_binary(file_path) ->
        Logger.info("Starting analysis for: #{file_path}")
        {:noreply, analyze_file(socket, file_path)}

      [] ->
        Logger.warning("No files were consumed")
        {:noreply, put_flash(socket, :error, "Please upload a file first")}

      error ->
        Logger.error("Upload consumption failed: #{inspect(error)}")
        {:noreply, put_flash(socket, :error, "Failed to process upload")}
    end
  end

  @impl true
  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    Logger.info("Canceling upload: #{ref}")
    {:noreply, cancel_upload(socket, :file, ref)}
  end

  @impl true
  def handle_event("clear", _params, socket) do
    Logger.info("Clearing analysis")

    {:noreply,
     socket
     |> assign(:media_schema, nil)
     |> assign(:file_path, nil)
     |> assign(:error, nil)}
  end

  defp handle_progress(:file, entry, socket) do
    Logger.debug("Upload progress: #{entry.client_name} - #{entry.progress}%")

    if entry.done? do
      Logger.info("Upload complete: #{entry.client_name}")
    end

    {:noreply, socket}
  end

  defp analyze_file(socket, path) do
    Logger.info("Starting file analysis: #{path}")
    Logger.info("File exists? #{File.exists?(path)}")
    Logger.info("File size: #{if File.exists?(path), do: File.stat!(path).size, else: "N/A"}")

    socket
    |> assign(:loading, true)
    |> assign(:error, nil)
    |> assign(:file_path, path)
    |> start_async(:analysis, fn ->
      Logger.info("Async analysis started for: #{path}")

      result =
        case Introspector.analyze(path) do
          {:ok, schema} ->
            Logger.info("Analysis successful!")
            Logger.debug("Schema: #{inspect(schema, pretty: true, limit: 5)}")
            {:ok, schema}

          {:error, reason} = error ->
            Logger.error("Analysis failed: #{inspect(reason)}")
            error
        end

      result
    end)
  end

  @impl true
  def handle_async(:analysis, {:ok, {:ok, schema}}, socket) do
    Logger.info("Analysis completed successfully")

    {:noreply,
     socket
     |> assign(:loading, false)
     |> assign(:media_schema, schema)
     |> put_flash(:info, "Analysis completed successfully")}
  end

  @impl true
  def handle_async(:analysis, {:ok, {:error, reason}}, socket) do
    Logger.error("Analysis failed: #{inspect(reason)}")

    error_msg =
      case reason do
        :file_not_found ->
          "File not found. Please upload a valid media file."

        {:ffprobe_failed, output} ->
          "FFprobe failed: #{String.slice(output, 0, 200)}"

        {:ffprobe_not_found, _} ->
          "FFprobe not found. Please ensure FFmpeg is installed."

        :invalid_json ->
          "Invalid FFprobe output. File may be corrupted."

        other ->
          "Analysis error: #{inspect(other)}"
      end

    {:noreply,
     socket
     |> assign(:loading, false)
     |> assign(:error, error_msg)
     |> put_flash(:error, error_msg)}
  end

  @impl true
  def handle_async(:analysis, {:exit, reason}, socket) do
    Logger.error("Analysis process exited: #{inspect(reason)}")

    {:noreply,
     socket
     |> assign(:loading, false)
     |> assign(:error, "Analysis failed: #{inspect(reason)}")
     |> put_flash(:error, "Analysis process failed")}
  end

  defp decode_file_param(nil), do: nil

  defp decode_file_param(path) when is_binary(path) do
    decoded = URI.decode_www_form(path)
    Logger.debug("Decoded file path: #{decoded}")

    if File.exists?(decoded) do
      decoded
    else
      Logger.warning("Decoded file does not exist: #{decoded}")
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
          <form id="upload-form" phx-submit="analyze" phx-change="validate">
            <%= if @uploads.file.entries == [] do %>
              <label 
                for={@uploads.file.ref}
                class="upload-zone" 
                phx-drop-target={@uploads.file.ref}
              >
                <.live_file_input upload={@uploads.file} class="hidden" />

                <div>
                  <div class="upload-icon">[F]</div>
                  <p class="upload-text">
                    DROP VIDEO FILE TO ANALYZE
                  </p>
                  <p class="upload-subtext">
                    or click to browse
                  </p>
                  <p class="upload-subtext mt-2">
                    Supported: MP4, MOV, MKV, AVI, WebM (max 500MB)
                  </p>
                </div>
              </label>
            <% else %>
              <.live_file_input upload={@uploads.file} class="hidden" />
              
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
                  <%= if @loading, do: "ANALYZING...", else: "ANALYZE FILE" %>
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
            <div class="animate-spin w-12 h-12 border-2 border-green rounded-full" style="border-top-color: transparent;">
            </div>
          </div>
          <p class="font-mono text-sm text-secondary animate-pulse">ANALYZING MEDIA FILE...</p>
          <p class="font-mono text-xs text-gray mt-2">Running ffprobe analysis</p>
          <%= if @file_path do %>
            <p class="font-mono text-xs text-gray mt-1"><%= Path.basename(@file_path) %></p>
          <% end %>
        </div>
      <% end %>

      <!-- Error State -->
      <%= if @error do %>
        <div class="flash flash-error">
          <div class="flex items-center gap-2 mb-2">
            <span class="text-red font-bold">[✕]</span>
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

  defp error_to_string(:too_large), do: "FILE TOO LARGE (max 500MB)"
  defp error_to_string(:too_many_files), do: "TOO MANY FILES (max 1)"
  defp error_to_string(:not_accepted), do: "FILE TYPE NOT ACCEPTED"
  defp error_to_string(err), do: "ERROR: #{inspect(err)}"
end
