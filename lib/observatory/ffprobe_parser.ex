defmodule Observatory.FFprobeParser do
  @moduledoc """
  Parses ffprobe JSON output into the Media schema

   This is a pure transformation module - no system calls.
  Expects JSON output from:
  
      ffprobe -v error -show_format -show_streams -print_format json input.mp4
  
  ## Responsibilities
  
  - Parse ffprobe JSON structure
  - Normalize field types (strings to numbers, tuples, etc.)
  - Map ffprobe keys to MediaSchema fields
  - Handle missing/optional fields gracefully
"""
  alias Observatory.MediaSchema 
  alias Observatory.MediaSchema.{Format, Stream}

  @doc """
   Parses ffprobe JSON string into MediaSchema.
  
  ## Expected JSON Structure
  
      {
        "format": {
          "filename": "/path/to/file.mp4",
          "format_name": "mov,mp4,m4a,3gp,3g2,mj2",
          "duration": "120.500000",
          "size": "36937500",
          "bit_rate": "2450000",
          "tags": {...}
        },
        "streams": [...]
      }
"""

  @spec parse(String.t()) :: {:ok,  MediaSchema.t()} | {:error, atom()}
  def parse(json_string) when is_binary(json_string) do
    with {:ok, data} <- decode_json(json_string),
         {:ok, format_data} <- extract_format(data),
         {:ok, stream_data} <- extract_streams(data) do
      build_schema(data["format"]["filename"], format_data, stream_data)
    end
  end

  def decode_json(json_string) do
    case Jason.decode(json_string) do
      {:ok, data} -> {:ok, data}
      {:error, _} -> {:error, :invalid_json}
    end
  end

  defp extract_format(%{"format" => format}) when is_map(format) do
    {:ok, format}
  end

  defp extract_format(_), do: {:error, :missing_format}
  
  defp extract_streams(%{"streams" => streams}) when is_list(streams) do
    {:ok, streams}
  end 

  defp extract_streams(_), do: {:error, :missing_streams} 

  def build_schema(file_path, format_data, streams_data) do
    schema = %MediaSchema{
      file_path: file_path || "unknown",
      format: parse_format(format_data),
      streams: Enum.map(streams_data, &parse_stream/1),
      analyzed_at: DateTime.utc_now()
    }
    {:ok, schema}
  end

  defp parse_format(data) do
    %Format{
      container_type: data["format_name"],
      duration_sec: parse_float(data["duration"]),
      size_bytes: parse_int(data["size"]),
      bitrate_bps: parse_int(data["bit_rate"]),
      metadata: data["tags"] || %{}
    }
  end

  defp parse_stream(data) do
    base_stream = %Stream{
      index: data["index"],
      type: parse_stream_type(data["codec_type"]),
      codec_name: data["codec_name"],
      codec_profile: data["profile"],
      timebase: parse_timebase(data["time_base"]),
      duration_sec: parse_float(data["duration"]),
      bitrate_bps: parse_int(data["bit_rate"])
    }

    case base_stream.type do
      :video -> add_video_fields(base_stream, data)
      :audio -> add_audio_fields(base_stream, data)
      _ -> base_stream
    end
  end

  defp parse_stream_type("video"), do: :video
  defp parse_stream_type("audio"), do: :audio
  defp parse_stream_type("subtitle"), do: :subtitle
  defp parse_stream_type(_), do: :unknown

  defp parse_timebase(nil), do: {1, 1000}
  defp parse_timebase(tb_string) when is_binary(tb_string) do
    case String.split(tb_string, "/") do
      [num_str, den_str] ->
        with {num, ""} <- Integer.parse(num_str),
             {den, ""} <- Integer.parse(den_str),
             true <- den > 0 do
          {num, den}
        else
          _ -> {1, 1000}
        end
      _ -> {1, 1000}
    end
  end

  defp parse_frame_rate(nil), do: nil
  defp parse_frame_rate(fr_string) when is_binary(fr_string) do
    case String.split(fr_string, "/") do
      [num_str, den_str] ->
        with {num, ""} <- Integer.parse(num_str),
             {den, ""} <- Integer.parse(den_str),
             true <- den > 0 do
          {num, den}
        else
          _ -> nil
        end
      _ -> nil
    end
  end

   defp add_video_fields(stream, data) do
    %{stream |
      width: data["width"],
      height: data["height"],
      frame_rate: parse_frame_rate(data["r_frame_rate"]),
      pixel_format: data["pix_fmt"],
      color_space: data["color_space"],
      color_range: data["color_range"]
    }
  end

   defp add_audio_fields(stream, data) do
    %{stream |
      sample_rate: parse_int(data["sample_rate"]),
      channels: data["channels"],
      channel_layout: data["channel_layout"]
    }
  end

  defp parse_float(nil), do: nil
  defp parse_float(val) when is_float(val), do: val
  defp parse_float(val) when is_integer(val), do: val / 1
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
