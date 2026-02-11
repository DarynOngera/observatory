defmodule Observatory.FrameParser do
  @moduledoc """
  Parses ffprobe frame data into structured GOPs.
  """

  alias Observatory.GOPStatsSchema
  alias Observatory.GOPStatsSchema.GOP

  @doc """
  Parses ffprobe frame JSON into GOPStats.

  ## Parameters

  - `json_string` - FFprobe JSON output
  - `media_file` - Path to media file
  - `stream_index` - Video stream index
  - `dimensions` - Optional {width, height} tuple for compression ratio calculation
  """
  @spec parse(String.t(), String.t(), non_neg_integer(), {pos_integer(), pos_integer()} | nil) ::
          {:ok, GOPStatsSchema.t()} | {:error, atom()}
  def parse(json_string, media_file, stream_index \\ 0, dimensions \\ nil)
      when is_binary(json_string) do
    with {:ok, data} <- decode_json(json_string),
         {:ok, frames} <- extract_frames(data) do
      build_gop_stats(frames, media_file, stream_index, dimensions)
    end
  end

  # Private functions

  defp decode_json(json_string) do
    case Jason.decode(json_string) do
      {:ok, data} -> {:ok, data}
      {:error, _} -> {:error, :invalid_json}
    end
  end

  defp extract_frames(%{"frames" => frames}) when is_list(frames) and length(frames) > 0 do
    {:ok, frames}
  end

  defp extract_frames(_), do: {:error, :no_frames}

  defp build_gop_stats(frames, media_file, stream_index, dimensions) do
    parsed_frames =
      frames
      |> Enum.with_index()
      |> Enum.map(fn {frame_data, idx} -> parse_frame(frame_data, idx) end)

    gops = group_into_gops(parsed_frames, dimensions)

    keyframe_positions = extract_keyframe_positions(parsed_frames)

    stats = GOPStatsSchema.calculate_stats(gops, length(parsed_frames))

    gop_stats = %GOPStatsSchema{
      media_file: media_file,
      video_stream_index: stream_index,
      total_frames: length(parsed_frames),
      gops: gops,
      keyframe_positions: keyframe_positions,
      stats: stats
    }

    {:ok, gop_stats}
  end

  defp parse_frame(data, frame_number) do
    %{
      frame_number: frame_number,
      pict_type: data["pict_type"] || "?",
      pts_time: parse_float(data["pkt_pts_time"]) || 0.0,
      pkt_size: parse_int(data["pkt_size"]) || 0,
      key_frame: data["key_frame"] == 1
    }
  end

  defp group_into_gops(frames, dimensions) do
    frames
    |> Enum.chunk_by(& &1.key_frame)
    |> Enum.reduce({[], []}, fn chunk, {gops, current_gop} ->
      case chunk do
        [%{key_frame: true} | _] = keyframe_chunk ->
          completed_gop =
            if current_gop != [], do: [build_gop(current_gop, length(gops), dimensions)], else: []

          {gops ++ completed_gop, keyframe_chunk}

        non_keyframe_chunk ->
          {gops, current_gop ++ non_keyframe_chunk}
      end
    end)
    |> then(fn {gops, last_gop} ->
      if last_gop != [] do
        gops ++ [build_gop(last_gop, length(gops), dimensions)]
      else
        gops
      end
    end)
  end

  defp build_gop(frames, gop_index, dimensions) when length(frames) > 0 do
    first_frame = List.first(frames)
    last_frame = List.last(frames)

    structure = Enum.map(frames, & &1.pict_type)
    total_bytes = Enum.sum(Enum.map(frames, & &1.pkt_size))

    i_frame = List.first(frames)
    i_frame_bytes = i_frame.pkt_size

    # Calculate compression ratio if dimensions available
    compression_ratio = calculate_compression_ratio(total_bytes, length(frames), dimensions)

    %GOP{
      index: gop_index,
      start_frame: first_frame.frame_number,
      end_frame: last_frame.frame_number,
      start_pts_sec: first_frame.pts_time,
      end_pts_sec: last_frame.pts_time,
      duration_sec: last_frame.pts_time - first_frame.pts_time,
      frame_count: length(frames),
      structure: structure,
      total_bytes: total_bytes,
      i_frame_bytes: i_frame_bytes,
      compression_ratio: compression_ratio
    }
  end

  defp calculate_compression_ratio(_total_bytes, _frame_count, nil), do: nil

  defp calculate_compression_ratio(total_bytes, frame_count, {width, height}) do
    # Uncompressed size: width * height * 3 bytes (RGB) * frame_count
    # Or for YUV 4:2:0: width * height * 1.5 bytes
    # Using YUV 4:2:0 as it's more common
    uncompressed_bytes = width * height * 1.5 * frame_count

    if uncompressed_bytes > 0 do
      uncompressed_bytes / total_bytes
    else
      nil
    end
  end

  defp extract_keyframe_positions(frames) do
    frames
    |> Enum.filter(& &1.key_frame)
    |> Enum.map(&{&1.pts_time, &1.frame_number})
  end

  defp parse_float(nil), do: nil
  defp parse_float(val) when is_float(val), do: val

  defp parse_float(val) when is_binary(val) do
    case Float.parse(val) do
      {float, _} -> float
      :error -> nil
    end
  end

  defp parse_int(nil), do: nil
  defp parse_int(val) when is_integer(val), do: val

  defp parse_int(val) when is_binary(val) do
    case Integer.parse(val) do
      {int, _} -> int
      :error -> nil
    end
  end
end
