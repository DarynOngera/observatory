defmodule Observatory.GOPAnalyzer do
  @moduledoc """
  Analyzes GOP structure of video files using ffprobe.
  """

  alias Observatory.{FrameParser, GOPStatsSchema, Introspector}

  @ffprobe_cmd "ffprobe"
  @ffprobe_args ~w(-v error -select_streams v:0 -show_frames -print_format json)

  @spec analyze(Path.t(), keyword()) :: {:ok, GOPStatsSchema.t()} | {:error, term()}
  def analyze(file_path, opts \\ []) do
    stream_index = Keyword.get(opts, :stream_index, 0)

    with :ok <- validate_file_exists(file_path),
         {:ok, media_schema} <- Introspector.analyze(file_path, opts),
         {:ok, json_output} <- run_ffprobe(file_path, stream_index, opts),
         {:ok, gop_stats} <-
           parse_with_dimensions(json_output, file_path, stream_index, media_schema) do
      {:ok, gop_stats}
    end
  end

  # Private functions

  defp parse_with_dimensions(json_output, file_path, stream_index, media_schema) do
    # Get video stream dimensions
    video_stream =
      media_schema.streams
      |> Enum.find(&(&1.type == :video && &1.index == stream_index))

    dimensions =
      case video_stream do
        %{width: w, height: h} when is_integer(w) and is_integer(h) ->
          {w, h}

        _ ->
          nil
      end

    FrameParser.parse(json_output, file_path, stream_index, dimensions)
  end

  defp validate_file_exists(file_path) do
    if File.exists?(file_path) do
      :ok
    else
      {:error, :file_not_found}
    end
  end

  defp run_ffprobe(file_path, stream_index, opts) do
    ffprobe_cmd = Keyword.get(opts, :ffprobe_path, @ffprobe_cmd)

    args =
      @ffprobe_args ++
        ["-select_streams", "v:#{stream_index}", file_path]

    case System.cmd(ffprobe_cmd, args, stderr_to_stdout: true) do
      {output, 0} ->
        {:ok, output}

      {error_output, _exit_code} ->
        {:error, {:ffprobe_failed, error_output}}
    end
  rescue
    e in ErlangError ->
      {:error, {:ffprobe_not_found, e}}
  end
end
