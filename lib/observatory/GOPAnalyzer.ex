defmodule Observatory.GOPAnalyzer do
  @moduledoc """
  Analyzes GOP structure of video files using ffprobe.
  
  This module makes system calls to ffprobe for frame-level analysis.
  
  ## Responsibilities
  
  - Execute ffprobe with -show_frames
  - Pass output to FrameParser
  - Return GOPStats
  """

  alias Observatory.{FrameParser, GOPStatsSchema}

  @ffprobe_cmd "ffprobe"
  @ffprobe_args ~w(-v error -select_streams v:0 -show_frames -print_format json)

  @doc """
  Analyzes GOP structure of a video file.
  
  Options
  
  - `:stream_index` - Video stream to analyze (default: 0)
  - `:ffprobe_path` - Custom path to ffprobe binary
  
  Returns
  
  - `{:ok, %GOPStats{}}` - Successfully analyzed
  - `{:error, :file_not_found}` - File does not exist
  - `{:error, {:ffprobe_failed, output}}` - ffprobe failed
  - `{:error, atom()}` - Parser errors
  
  Examples
  
      iex> GOPAnalyzer.analyze("video.mp4")
      {:ok, %GOPStats{...}}
  """
  @spec analyze(Path.t(), keyword()) :: {:ok, GOPStatsSchema.t()} | {:error, term()}
  def analyze(file_path, opts \\ []) do
    stream_index = Keyword.get(opts, :stream_index, 0)

    with :ok <- validate_file_exists(file_path),
         {:ok, json_output} <- run_ffprobe(file_path, stream_index, opts),
         {:ok, gop_stats} <- FrameParser.parse(json_output, file_path, stream_index) do
      {:ok, gop_stats}
    end
  end

  # Private functions

  defp validate_file_exists(file_path) do
    if File.exists?(file_path) do
      :ok
    else
      {:error, :file_not_found}
    end
  end

  defp run_ffprobe(file_path, stream_index, opts) do
    ffprobe_cmd = Keyword.get(opts, :ffprobe_path, @ffprobe_cmd)
    
    # Build args with specific stream selection
    args = @ffprobe_args ++ 
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
