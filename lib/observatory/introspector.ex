defmodule Observatory.Introspector do
  @moduledoc """
  Analyzes media files using ffprobe.
  
  This is the ONLY module that makes system calls to ffprobe.
  All other modules work with the resulting MediaSchema.
  
  Responsibilities
  
  - Validate file existence
  - Execute ffprobe binary
  - Pass JSON output to FFprobeParser
  - Return MediaSchema or error
"""

  alias Observatory.{FFprobeParser, MediaSchema}

  @ffprobe_cmd "ffprobe"
  @ffprobe_args ~w(-v error -show_format -show_streams -print_format json)

  @doc """
  Analyzes a media file and returns MediaSchema.
  
  ## Options
  
  - `:ffprobe_path` - Custom path to ffprobe binary (default: "ffprobe")
  
  ## Returns
  
  - `{:ok, %MediaSchema{}}` - Successfully analyzed
  - `{:error, :file_not_found}` - File does not exist
  - `{:error, {:ffprobe_failed, output}}` - ffprobe returned error
  - `{:error, {:ffprobe_not_found, error}}` - ffprobe binary not found
  - `{:error, atom()}` - Parser errors (invalid_json, etc.)
  
  ## Examples
  
      iex> Introspector.analyze("test/fixtures/sample.mp4")
      {:ok, %MediaSchema{...}}
      
      iex> Introspector.analyze("/nonexistent/file.mp4")
      {:error, :file_not_found}
"""

  @spec analyze(Path.t(), keyword()) :: {:ok, MediaSchema.t()} | {:error, term()}
  def analyze(file_path, opts \\ []) do
    with :ok <- validate_file_exists(file_path),
      {:ok, json_output} <- run_ffprobe(file_path, opts),
      {:ok, schema} <- FFprobeParser.parse(json_output) do
      {:ok, %{schema | file_path: file_path}}
    end
  end

  @spec ffprobe_available?(keyword()) :: boolean()
  def ffprobe_available?(opts \\ []) do
    ffprobe_cmd = Keyword.get(opts, :ffprobe_path, @ffprobe_cmd)
    
    case System.cmd(ffprobe_cmd, ["-version"], stderr_to_stdout: true) do
      {output, 0} ->
        String.contains?(output, "ffprobe version")
      _ ->
        false
    end
  rescue 
    _ ->
      false 
  end

  @spec ffprobe_version(keyword()) :: {:ok, String.t()} | {:error, term()}
  def ffprobe_version(opts \\ []) do
    ffprobe_cmd = Keyword.get(opts, :ffprobe_path, @ffprobe_cmd)

    case System.cmd(ffprobe_cmd, ["-version"], stderr_to_stdout: true) do
      {output, 0} ->
        version = 
          output
          |> String.split("\n")
          |> hd()
        {:ok, version}
      {error, _} -> {:error, {:ffprobe_failed, error}}
    end
  rescue
    e -> {:error, {:ffprobe_not_found, e}}
  end

  defp validate_file_exists(file_path) do
    if File.exists?(file_path) do
      :ok
    else
      {:ok, :file_not_found}
    end
  end

  defp run_ffprobe(file_path, opts) do
    ffprobe_cmd = Keyword.get(opts, :ffprobe_path, @ffprobe_cmd)
    args = @ffprobe_args ++ [file_path]

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
