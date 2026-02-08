defmodule Observatory.ParserTest do
  use ExUnit.Case, async: true 

  alias Observatory.FFprobeParser 
  alias Observatory.MediaSchema 
  alias Observatory.MediaSchema.{Format, Stream}

   @sample_mp4_output """
  {
    "streams": [
      {
        "index": 0,
        "codec_name": "h264",
        "codec_type": "video",
        "profile": "High",
        "width": 1920,
        "height": 1080,
        "r_frame_rate": "30/1",
        "time_base": "1/90000",
        "duration": "120.500000",
        "bit_rate": "2100000",
        "pix_fmt": "yuv420p",
        "color_space": "bt709",
        "color_range": "tv"
      },
      {
        "index": 1,
        "codec_name": "aac",
        "codec_type": "audio",
        "profile": "LC",
        "sample_rate": "48000",
        "channels": 2,
        "channel_layout": "stereo",
        "time_base": "1/48000",
        "duration": "120.480000",
        "bit_rate": "128000"
      }
    ],
    "format": {
      "filename": "/tmp/test.mp4",
      "format_name": "mov,mp4,m4a,3gp,3g2,mj2",
      "duration": "120.500000",
      "size": "36937500",
      "bit_rate": "2450000",
      "tags": {
        "major_brand": "isom",
        "minor_version": "512",
        "compatible_brands": "isomiso2avc1mp41"
      }
    }
  }
  """

  
  describe "parse/1 with MP4 output" do
    test "successfully parses complete ffprobe output" do
      assert {:ok, schema} = FFprobeParser.parse(@sample_mp4_output)

      assert %MediaSchema{} = schema
      assert schema.file_path == "/tmp/test.mp4"
      assert %Format{} = schema.format
      assert is_list(schema.streams)
      assert length(schema.streams) == 2
      assert %DateTime{} = schema.analyzed_at
    end
  end

   test "parses format metadata tags" do
      {:ok, schema} = FFprobeParser.parse(@sample_mp4_output)

      assert schema.format.metadata["major_brand"] == "isom"
      assert schema.format.metadata["minor_version"] == "512"
      assert schema.format.metadata["compatible_brands"] == "isomiso2avc1mp41"
    end

   test "handles missing metadata tags" do
      json = """
      {
        "format": {
          "filename": "/tmp/test.mp4",
          "format_name": "mp4",
          "duration": "10.0",
          "size": "1000000",
          "bit_rate": "800000"
        },
        "streams": []
      }
      """

      {:ok, schema} = FFprobeParser.parse(json)

      assert schema.format.metadata == %{}
    end

end
