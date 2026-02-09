defmodule Observatory.FrameParser do
  @moduledoc """
  Parses ffprobe frame data into structured GOPs.
  
  This is a pure transformation module - no system calls.
  Expects JSON output from:
  
      ffprobe -v error -select_streams v:0 -show_frames -print_format json input.mp4
  
  Responsibilities
  
  - Parse frame-level JSON from ffprobe
  - Group frames into GOPs (by I-frame boundaries)
  - Calculate GOP statistics
  - Extract keyframe positions
  """

  alias Observatory.GOPStatsSchema
  alias Observatory.GOPStatsSchema.GOP

  @doc """
  Parses ffprobe frame JSON into GOPStats.
  
  Returns
  
  - `{:ok, %GOPStats{}}` - Successfully parsed
  - `{:error, :invalid_json}` - JSON decode failed
  - `{:error, :no_frames}` - No frames in output
  """
  @spec parse(String.t(), String.t(), non_neg_integer()) ::
          {:ok, GOPStatsSchema.t()} | {:error, atom()}
  def parse(json_string, media_file, stream_index \\ 0)
      when is_binary(json_string) do
    with {:ok, data} <- decode_json(json_string),
         {:ok, frames} <- extract_frames(data) do
      build_gop_stats(frames, media_file, stream_index)
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

  defp build_gop_stats(frames, media_file, stream_index) do
    parsed_frames =
      frames
      |> Enum.with_index()
      |> Enum.map(fn {frame_data, idx} -> parse_frame(frame_data, idx) end)

    gops = group_into_gops(parsed_frames)

    # Extract keyframe positions
    keyframe_positions = extract_keyframe_positions(parsed_frames)

    # Calculate aggregate stats
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

  defp group_into_gops(frames) do
    frames
    |> Enum.chunk_by(& &1.key_frame)
    |> Enum.reduce({[], []}, fn chunk, {gops, current_gop} ->
      case chunk do
        # Start of new GOP (keyframe)
        [%{key_frame: true} | _] = keyframe_chunk ->
          # Save previous GOP if it exists
          completed_gop = if current_gop != [], do: [build_gop(current_gop, length(gops))], else: []
          {gops ++ completed_gop, keyframe_chunk}

        # Non-keyframes - add to current GOP
        non_keyframe_chunk ->
          {gops, current_gop ++ non_keyframe_chunk}
      end
    end)
    |> then(fn {gops, last_gop} ->
      # Add final GOP
      if last_gop != [] do
        gops ++ [build_gop(last_gop, length(gops))]
      else
        gops
      end
    end)
  end

  defp build_gop(frames, gop_index) when length(frames) > 0 do
    first_frame = List.first(frames)
    last_frame = List.last(frames)

    structure = Enum.map(frames, & &1.pict_type)
    total_bytes = Enum.sum(Enum.map(frames, & &1.pkt_size))
    
    # I-frame is always first in GOP
    i_frame = List.first(frames)
    i_frame_bytes = i_frame.pkt_size

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
      compression_ratio: nil  # Could calculate if we had frame dimensions
    }
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
