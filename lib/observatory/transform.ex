defmodule Mix.Tasks.Observatory.Transform do
  @moduledoc """
  Transform media files using Membrane pipelines.
  """

  use Mix.Task

  alias Observatory.{Transformer, ProcessSchema}

  @shortdoc "Transform media with Membrane"

  def run([input_file, output_file | args]) do
    Mix.Task.run("app.start")

    opts = parse_opts(args)
    config = build_config(opts)

    IO.puts("\n=== Membrane Transformation ===\n")
    IO.puts("Input:  #{input_file}")
    IO.puts("Output: #{output_file}")
    IO.puts("\nConfiguration:")
    IO.puts("  Codec: #{config.codec || "copy"}")
    IO.puts("  Preset: #{config.preset || "N/A"}")
    IO.puts("  CRF: #{config.crf || "N/A"}")
    IO.puts("  GOP Size: #{config.gop_size || "N/A"}")
    IO.puts("")

    compare? = Keyword.get(opts, :compare, false)

    result =
      if compare? do
        transform_with_comparison(input_file, output_file, config)
      else
        transform_simple(input_file, output_file, config)
      end

    case result do
      {:ok, _} ->
        IO.puts("\n✅ Transformation complete!\n")

      {:error, reason} ->
        IO.puts("\n❌ Transformation failed: #{inspect(reason)}\n")
    end
  end

  def run(_) do
    IO.puts(@moduledoc)
  end

  defp parse_opts(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        strict: [
          codec: :string,
          preset: :string,
          crf: :integer,
          gop: :integer,
          compare: :boolean
        ]
      )

    opts
  end

  defp build_config(opts) do
    %ProcessSchema.TransformConfig{
      # nil means no transcode
      codec: Keyword.get(opts, :codec),
      container: "mp4",
      preset: Keyword.get(opts, :preset),
      crf: Keyword.get(opts, :crf),
      gop_size: Keyword.get(opts, :gop)
    }
  end

  defp transform_simple(input_file, output_file, config) do
    Transformer.transform(
      input_file,
      output_file,
      config,
      progress_callback: &print_progress/1
    )
  end

  defp transform_with_comparison(input_file, output_file, config) do
    IO.puts("Analyzing input...")

    result =
      Transformer.transform_and_compare(
        input_file,
        output_file,
        config,
        progress_callback: &print_progress/1
      )

    case result do
      {:ok, comparison} ->
        print_comparison(comparison)
        {:ok, comparison}

      error ->
        error
    end
  end

  defp print_progress(process) do
    case process.status do
      :running ->
        if length(process.events) > 0 do
          last_event = List.last(process.events)

          if last_event.type == :progress do
            frames = last_event.data[:frames_processed]
            fps = last_event.data[:fps]

            if frames && fps do
              IO.write("\rFrames: #{frames} | FPS: #{Float.round(fps, 1)}")
            end
          end
        end

      :completed ->
        IO.puts("\n✓ Pipeline completed")

      :failed ->
        IO.puts("\n✗ Pipeline failed: #{process.error}")

      _ ->
        :ok
    end
  end

  defp print_comparison(comparison) do
    IO.puts("\n\n=== Comparison Results ===\n")

    metrics = comparison.metrics

    IO.puts("File Size:")
    IO.puts("  Input:  #{format_bytes(comparison.input_schema.format.size_bytes)}")
    IO.puts("  Output: #{format_bytes(comparison.output_schema.format.size_bytes)}")
    IO.puts("  Change: #{format_percentage(metrics.size_reduction)} reduction")

    IO.puts("\nBitrate:")
    IO.puts("  Input:  #{format_bitrate(comparison.input_schema.format.bitrate_bps)}")
    IO.puts("  Output: #{format_bitrate(comparison.output_schema.format.bitrate_bps)}")
    IO.puts("  Change: #{format_percentage(metrics.bitrate_change)}")

    IO.puts("\nGOP Structure:")

    IO.puts(
      "  Input Avg GOP Size:  #{Float.round(comparison.input_gop_stats.stats.avg_gop_size, 1)} frames"
    )

    IO.puts(
      "  Output Avg GOP Size: #{Float.round(comparison.output_gop_stats.stats.avg_gop_size, 1)} frames"
    )

    IO.puts("  Change: #{format_percentage(metrics.gop_size_change)}")

    IO.puts("\nSeekability:")
    IO.puts("  Input:  #{Float.round(comparison.input_gop_stats.stats.seekability_score, 1)}/100")

    IO.puts(
      "  Output: #{Float.round(comparison.output_gop_stats.stats.seekability_score, 1)}/100"
    )

    IO.puts("  Change: #{format_change(metrics.seekability_change)} points")
  end

  defp format_bytes(bytes) when bytes < 1024, do: "#{bytes} B"

  defp format_bytes(bytes) when bytes < 1024 * 1024 do
    "#{Float.round(bytes / 1024, 1)} KB"
  end

  defp format_bytes(bytes) do
    "#{Float.round(bytes / 1024 / 1024, 2)} MB"
  end

  defp format_bitrate(bps) do
    "#{Float.round(bps / 1000, 0)} kbps"
  end

  defp format_percentage(value) when value > 0, do: "+#{value}%"
  defp format_percentage(value), do: "#{value}%"

  defp format_change(value) when value > 0, do: "+#{value}"
  defp format_change(value), do: "#{value}"
end
