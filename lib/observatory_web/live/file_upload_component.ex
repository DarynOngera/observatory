defmodule ObservatoryWeb.FileUploadComponent do
  @moduledoc """
  Terminal-styled file upload component.
  """
  use ObservatoryWeb, :live_component

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <!-- Upload Zone - uses label to trigger file input -->
      <label
        for={@uploads.file.ref}
        class={if @drag_active, do: "upload-zone drag-active", else: "upload-zone"}
        phx-drop-target={@uploads.file.ref}
        phx-hook="DragAndDrop"
        id="upload-zone"
      >
        <.live_file_input upload={@uploads.file} class="hidden" />

        <div>
          <div class="upload-icon">+</div>
          <p class="upload-text">
            DROP VIDEO FILE
          </p>
          <p class="upload-subtext">
            or click to browse
          </p>
          <p class="upload-subtext mt-4">
            MP4, MOV, MKV, AVI up to 500MB
          </p>
        </div>
      </label>

      <!-- Selected File Info -->
      <%= for entry <- @uploads.file.entries do %>
        <div class="card mt-6">
          <div class="flex items-center justify-between">
            <div class="flex items-center gap-3">
              <div class="w-12 h-12 border flex items-center justify-center">
                <span class="font-mono">[F]</span>
              </div>
              <div>
                <p class="font-mono text-sm text-green font-bold">
                  <%= entry.client_name %>
                </p>
                <p class="font-mono text-xs text-gray">
                  <%= format_bytes(entry.client_size) %>
                </p>
              </div>
            </div>

            <div class="flex items-center gap-3">
              <!-- Progress -->
              <%= if entry.progress < 100 do %>
                <div class="w-32">
                  <div class="w-full bg-gray-200 rounded-full h-2 overflow-hidden">
                    <div 
                      class="bg-green h-full transition-all duration-300"
                      style={"width: #{entry.progress}%"}
                    ></div>
                  </div>
                </div>
                <span class="font-mono text-xs text-green w-12 text-right">
                  <%= entry.progress %>%
                </span>
              <% else %>
                <span class="font-mono text-xs text-green">READY</span>
              <% end %>

              <!-- Cancel button -->
              <button
                type="button"
                phx-click="cancel-upload"
                phx-target={@myself}
                phx-value-ref={entry.ref}
                class="btn btn-secondary text-xs px-2 py-1"
              >
                X
              </button>
            </div>
          </div>

          <!-- Errors -->
          <%= for err <- upload_errors(@uploads.file, entry) do %>
            <div class="flash flash-error mt-4">
              ERROR: <%= error_to_string(err) %>
            </div>
          <% end %>
        </div>
      <% end %>

      <!-- Upload Button -->
      <%= if length(@uploads.file.entries) > 0 && Enum.all?(@uploads.file.entries, &(&1.progress == 100)) do %>
        <div class="mt-6 text-center">
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
