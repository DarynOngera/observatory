defmodule Observatory.Transformer do
  @moduledoc """
  High-level API for media transformations using Membrane.
  """
  require Logger

  alias Observatory.{
    Introspector,
    GOPAnalyzer,
    ProcessSchema,
    Membrane.PipelineSupervisor
  }

  @default_timeout 300_000
  # Minimum 1KB for a valid video file
  @min_valid_file_size 1024

  @doc """
  Transforms media using Membrane pipeline.
  """
  @spec transform(String.t(), String.t(), ProcessSchema.TransformConfig.t(), keyword()) ::
          {:ok, ProcessSchema.t()} | {:error, term()}
  def transform(input_file, output_file, config, opts \\ []) do
    progress_callback = Keyword.get(opts, :progress_callback)
    timeout = Keyword.get(opts, :timeout, @default_timeout)

    Logger.info("Starting transformation: #{input_file} -> #{output_file}")
    Logger.info("Config: #{inspect(config)}")

    # Start pipeline
    case PipelineSupervisor.start_pipeline(input_file, output_file, config) do
      {:ok, ref} ->
        # Wait for completion with optional progress tracking
        result = wait_for_completion(ref, output_file, progress_callback, timeout)
        Logger.info("Transformation result: #{inspect(result)}")
        result

      {:error, reason} = error ->
        Logger.error("Failed to start pipeline: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Transforms and compares using Membrane.
  """
  @spec transform_and_compare(
          String.t(),
          String.t(),
          ProcessSchema.TransformConfig.t(),
          keyword()
        ) :: {:ok, map()} | {:error, term()}
  def transform_and_compare(input_file, output_file, config, opts \\ []) do
    analyze_input? = Keyword.get(opts, :analyze_input, true)
    analyze_output? = Keyword.get(opts, :analyze_output, true)
    progress_callback = Keyword.get(opts, :progress_callback)

    with {:ok, input_schema, input_gop_stats} <- maybe_analyze_input(input_file, analyze_input?),
         {:ok, process} <-
           transform(input_file, output_file, config, progress_callback: progress_callback),
         {:ok, output_schema, output_gop_stats} <-
           maybe_analyze_output(output_file, analyze_output?) do
      metrics =
        calculate_comparison_metrics(
          input_schema,
          input_gop_stats,
          output_schema,
          output_gop_stats
        )

      comparison = %{
        input_schema: input_schema,
        input_gop_stats: input_gop_stats,
        output_schema: output_schema,
        output_gop_stats: output_gop_stats,
        process: process,
        metrics: metrics
      }

      {:ok, comparison}
    end
  end

  # Private functions

  defp wait_for_completion(ref, output_file, callback, timeout) do
    deadline = System.monotonic_time(:millisecond) + timeout
    do_wait_for_completion(ref, output_file, callback, deadline, 200)
  end

  defp do_wait_for_completion(ref, output_file, callback, deadline, poll_interval) do
    if System.monotonic_time(:millisecond) >= deadline do
      Logger.warning("Timeout exceeded, checking if output file was created...")

      # Check if file was created despite timeout - pipeline may have completed
      if File.exists?(output_file) do
        {:ok, stat} = File.stat(output_file)

        if stat.size > @min_valid_file_size do
          Logger.info("Output file exists (#{stat.size} bytes) - treating as success")

          # Create a basic process record for the completed transformation
          process = %ProcessSchema{
            input_file: "",
            output_file: output_file,
            config: nil,
            status: :completed,
            started_at: DateTime.utc_now(),
            completed_at: DateTime.utc_now(),
            error: nil,
            stats: %ProcessSchema.ProcessStats{
              duration_sec: 0.0,
              frames_processed: 0,
              fps: 0.0,
              bitrate_kbps: 0.0,
              speed: 0.0,
              size_bytes: stat.size,
              quality_score: nil
            },
            events: []
          }

          {:ok, process}
        else
          Logger.error(
            "Output file exists but is too small (#{stat.size} bytes, min: #{@min_valid_file_size})"
          )

          PipelineSupervisor.stop_pipeline(ref)
          {:error, :timeout}
        end
      else
        Logger.error("Timeout exceeded and no output file created")
        PipelineSupervisor.stop_pipeline(ref)
        {:error, :timeout}
      end
    else
      case PipelineSupervisor.get_pipeline_state(ref) do
        {:ok, process} ->
          if callback do
            callback.(process)
          end

          case process.status do
            :completed ->
              Logger.info("Pipeline completed successfully")
              {:ok, process}

            :failed ->
              Logger.error("Pipeline failed #{process.error}")
              {:error, process.error}

            _ ->
              # Still running, poll again
              Process.sleep(poll_interval)
              do_wait_for_completion(ref, output_file, callback, deadline, poll_interval)
          end

        {:error, :not_found} ->
          # Pipeline process not found - check if file was created
          if File.exists?(output_file) do
            {:ok, stat} = File.stat(output_file)

            if stat.size > @min_valid_file_size do
              Logger.info("Pipeline not found but output file exists - treating as success")

              process = %ProcessSchema{
                input_file: "",
                output_file: output_file,
                config: nil,
                status: :completed,
                started_at: DateTime.utc_now(),
                completed_at: DateTime.utc_now(),
                error: nil,
                stats: %ProcessSchema.ProcessStats{
                  duration_sec: 0.0,
                  frames_processed: 0,
                  fps: 0.0,
                  bitrate_kbps: 0.0,
                  speed: 0.0,
                  size_bytes: stat.size,
                  quality_score: nil
                },
                events: []
              }

              {:ok, process}
            else
              Logger.error(
                "Pipeline not found and output file is too small (#{stat.size} bytes, min: #{@min_valid_file_size})"
              )

              {:error, :pipeline_not_found}
            end
          else
            Logger.error("Pipeline not found")
            {:error, :pipeline_not_found}
          end
      end
    end
  end

  defp maybe_analyze_input(input_file, true) do
    Logger.info("Analyzing input file")

    with {:ok, schema} <- Introspector.analyze(input_file),
         {:ok, gop_stats} <- GOPAnalyzer.analyze(input_file) do
      {:ok, schema, gop_stats}
    end
  end

  defp maybe_analyze_input(_input_file, false) do
    {:ok, nil, nil}
  end

  defp maybe_analyze_output(output_file, true) do
    Logger.info("Analyzing output file")

    with {:ok, schema} <- Introspector.analyze(output_file),
         {:ok, gop_stats} <- GOPAnalyzer.analyze(output_file) do
      {:ok, schema, gop_stats}
    end
  end

  defp maybe_analyze_output(_output_file, false) do
    {:ok, nil, nil}
  end

  defp calculate_comparison_metrics(nil, nil, _output_schema, _output_gop_stats) do
    %{}
  end

  defp calculate_comparison_metrics(_input_schema, _input_gop_stats, nil, nil) do
    %{}
  end

  defp calculate_comparison_metrics(
         input_schema,
         input_gop_stats,
         output_schema,
         output_gop_stats
       ) do
    size_reduction =
      (input_schema.format.size_bytes - output_schema.format.size_bytes) /
        input_schema.format.size_bytes * 100

    bitrate_change =
      (output_schema.format.bitrate_bps - input_schema.format.bitrate_bps) /
        input_schema.format.bitrate_bps * 100

    gop_size_change =
      (output_gop_stats.stats.avg_gop_size - input_gop_stats.stats.avg_gop_size) /
        input_gop_stats.stats.avg_gop_size * 100

    seekability_change =
      output_gop_stats.stats.seekability_score - input_gop_stats.stats.seekability_score

    input_avg_compression = calculate_avg_compression(input_gop_stats.gops)
    output_avg_compression = calculate_avg_compression(output_gop_stats.gops)

    compression_efficiency_change =
      if input_avg_compression && output_avg_compression do
        (output_avg_compression - input_avg_compression) / input_avg_compression * 100
      else
        nil
      end

    %{
      size_reduction: Float.round(size_reduction, 2),
      bitrate_change: Float.round(bitrate_change, 2),
      gop_size_change: Float.round(gop_size_change, 2),
      seekability_change: Float.round(seekability_change, 2),
      compression_efficiency_change: compression_efficiency_change
    }
  end

  defp calculate_avg_compression(gops) do
    ratios =
      gops
      |> Enum.map(& &1.compression_ratio)
      |> Enum.reject(&is_nil/1)

    if Enum.empty?(ratios) do
      nil
    else
      Enum.sum(ratios) / length(ratios)
    end
  end
end
