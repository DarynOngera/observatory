defmodule ObservatoryWeb.FileUploadComponent do
  @moduledoc """
  Terminal-styled file upload component.
  """
  use ObservatoryWeb, :live_component

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <!-- Upload Zone -->
      <div
        class={if @drag_active, do: "upload-zone drag-active", else: "upload-zone"}
        phx-drop-target={@uploads.file.ref}
        phx-hook="DragAndDrop"
        id="upload-zone"
        phx-click={JS.dispatch("click", to: "#upload-zone input[type=file]")}
      >
        <.live_file_input upload={@uploads.file} class="hidden" />

        <div style="pointer-events: none;">
          <div class="upload-icon">+</div>
          <p class="upload-text">
            DROP VIDEO FILE
          </p>
          <p class="upload-subtext">
            or click to browse
          </p>
          <p class="upload-subtext" style="margin-top: 16px;">
            MP4, MOV, MKV, AVI up to 500MB
          </p>
        </div>
      </div>

      <!-- Selected File Info -->
      <%= for entry <- @uploads.file.entries do %>
        <div class="card" style="margin-top: 24px;">
          <div style="display: flex; align-items: center; justify-content: space-between;">
            <div style="display: flex; align-items: center; gap: 12px;">
              <div style="width: 40px; height: 40px; border: 2px solid #00ff00; display: flex; align-items: center; justify-content: center;">
                <span class="font-mono">[F]</span>
              </div>
              <div>
                <p style="font-size: 14px; font-weight: bold; color: #00ff00; font-family: monospace;">
                  <%= entry.client_name %>
                </p>
                <p style="font-size: 12px; color: #666666; font-family: monospace;">
                  <%= format_bytes(entry.client_size) %>
                </p>
              </div>
            </div>

            <div style="display: flex; align-items: center; gap: 12px;">
              <!-- Progress -->
              <%= if entry.progress < 100 do %>
                <div style="width: 128px;">
                  <div style="border: 2px solid #00ff00; overflow: hidden; height: 8px;">
                    <div style={"background: #00ff00; height: 100%; transition: width 0.3s ease; width: #{entry.progress}%;"}></div>
                  </div>
                </div>
                <span style="font-family: monospace; font-size: 12px; color: #00ff00; width: 48px; text-align: right;">
                  <%= entry.progress %>%
                </span>
              <% else %>
                <span style="font-family: monospace; font-size: 12px; color: #00ff00;">READY</span>
              <% end %>

              <!-- Cancel button -->
              <button
                type="button"
                phx-click="cancel-upload"
                phx-target={@myself}
                phx-value-ref={entry.ref}
                class="btn btn-secondary"
                style="padding: 4px 8px; font-size: 12px;"
              >
                X
              </button>
            </div>
          </div>

          <!-- Errors -->
          <%= for err <- upload_errors(@uploads.file, entry) do %>
            <div class="flash flash-error" style="margin-top: 16px;">
              ERROR: <%= error_to_string(err) %>
            </div>
          <% end %>
        </div>
      <% end %>

      <!-- Upload Button -->
      <%= if length(@uploads.file.entries) > 0 && Enum.all?(@uploads.file.entries, &(&1.progress == 100)) do %>
        <div style="margin-top: 24px; text-align: center;">
          <button
            type="button"
            phx-click={@on_analyze}
            class="btn"
          >
            <%= @action_label %>
          </button>
        </div>
      <% end %>
    </div>
    """
  end

  @impl true
  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :file, ref)}
  end

  defp format_bytes(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_bytes(bytes) when bytes < 1024 * 1024, do: "#{Float.round(bytes / 1024, 1)} KB"
  defp format_bytes(bytes), do: "#{Float.round(bytes / 1024 / 1024, 2)} MB"

  defp error_to_string(:too_large), do: "FILE TOO LARGE"
  defp error_to_string(:too_many_files), do: "TOO MANY FILES"
  defp error_to_string(:not_accepted), do: "FILE TYPE NOT ACCEPTED"
  defp error_to_string(err), do: "UNKNOWN ERROR: #{inspect(err)}"
end
