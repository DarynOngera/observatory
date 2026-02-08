defmodule Observatory.MediaSchemaTest do
  use ExUnit.Case, async: true

  alias Observatory.MediaSchema
  alias Observatory.MediaSchema.{Format, Stream}


  describe "MediaSchema struct" do
    test "creates valid schema with all required fields" do
      schema = %MediaSchema{
        file_path: "/tmp/test.mp4",
        format: %Format{
          container_type: "mov,mp4,m4a,3gp,3g2,mj2",
          duration_sec: 120.5,
          size_bytes: 36_937_500,
          bitrate_bps: 2_450_000
        },
        streams: [
          %Stream{
            index: 0,
            type: :video,
            codec_name: "h264",
            codec_profile: "High",
            timebase: {1, 90000},
            width: 1920,
            height: 1080,
            frame_rate: {30, 1}
          }
        ],
        analyzed_at: DateTime.utc_now()
      }

      assert schema.file_path == "/tmp/test.mp4"
      assert schema.format.duration_sec == 120.5
      assert length(schema.streams) == 1
      assert hd(schema.streams).type == :video
    end

    test "requires all mandatory fields" do
      assert_raise ArgumentError, fn ->
        %MediaSchema{file_path: "/tmp/test.mp4"}
      end
    end

    test "supports multiple streams of different types" do
      schema = %MediaSchema{
        file_path: "/tmp/test.mp4",
        format: %Format{
          container_type: "mp4",
          duration_sec: 60.0,
          size_bytes: 10_000_000,
          bitrate_bps: 1_333_333
        },
        streams: [
          %Stream{
            index: 0,
            type: :video,
            codec_name: "h264",
            timebase: {1, 90000}
          },
          %Stream{
            index: 1,
            type: :audio,
            codec_name: "aac",
            timebase: {1, 48000}
          },
          %Stream{
            index: 2,
            type: :subtitle,
            codec_name: "mov_text",
            timebase: {1, 1000}
          }
        ],
        analyzed_at: DateTime.utc_now()
      }

      assert length(schema.streams) == 3
      assert Enum.any?(schema.streams, &(&1.type == :video))
      assert Enum.any?(schema.streams, &(&1.type == :audio))
      assert Enum.any?(schema.streams, &(&1.type == :subtitle))
    end
  end

  describe "Format struct" do
    test "creates valid format with required fields" do
      format = %Format{
        container_type: "matroska,webm",
        duration_sec: 60.0,
        size_bytes: 1_000_000,
        bitrate_bps: 133_333
      }

      assert format.container_type == "matroska,webm"
      assert format.duration_sec == 60.0
      assert format.size_bytes == 1_000_000
      assert format.bitrate_bps == 133_333
    end

    test "defaults metadata to empty map" do
      format = %Format{
        container_type: "matroska,webm",
        duration_sec: 60.0,
        size_bytes: 1_000_000,
        bitrate_bps: 133_333
      }

      assert format.metadata == %{}
    end

    test "accepts custom metadata" do
      format = %Format{
        container_type: "mp4",
        duration_sec: 120.0,
        size_bytes: 5_000_000,
        bitrate_bps: 333_333,
        metadata: %{
          "title" => "Test Video",
          "artist" => "Test Artist",
          "major_brand" => "isom"
        }
      }

      assert format.metadata["title"] == "Test Video"
      assert format.metadata["major_brand"] == "isom"
    end

    test "requires all mandatory fields" do
      assert_raise ArgumentError, fn ->
        %Format{}
      end

      assert_raise ArgumentError, fn ->
        %Format{container_type: "mp4"}
      end
    end
  end

  describe "Stream struct - common fields" do
    test "creates valid video stream" do
      stream = %Stream{
        index: 0,
        type: :video,
        codec_name: "h264",
        codec_profile: "High",
        timebase: {1, 90000},
        duration_sec: 120.0,
        bitrate_bps: 2_000_000,
        width: 1920,
        height: 1080,
        frame_rate: {30, 1},
        pixel_format: "yuv420p"
      }

      assert stream.index == 0
      assert stream.type == :video
      assert stream.codec_name == "h264"
      assert stream.timebase == {1, 90000}
    end

    test "creates valid audio stream" do
      stream = %Stream{
        index: 1,
        type: :audio,
        codec_name: "aac",
        codec_profile: "LC",
        timebase: {1, 48000},
        duration_sec: 120.0,
        bitrate_bps: 128_000,
        sample_rate: 48000,
        channels: 2,
        channel_layout: "stereo"
      }

      assert stream.index == 1
      assert stream.type == :audio
      assert stream.codec_name == "aac"
      assert stream.timebase == {1, 48000}
    end

    test "supports all stream types" do
      for type <- [:video, :audio, :subtitle, :unknown] do
        stream = %Stream{
          index: 0,
          type: type,
          codec_name: "test",
          timebase: {1, 1000}
        }

        assert stream.type == type
      end
    end

    test "requires mandatory fields" do
      assert_raise ArgumentError, fn ->
        %Stream{}
      end

      assert_raise ArgumentError, fn ->
        %Stream{index: 0, type: :video, codec_name: "h264"}
      end
    end

    test "allows nil for optional fields" do
      stream = %Stream{
        index: 0,
        type: :video,
        codec_name: "h264",
        timebase: {1, 90000},
        codec_profile: nil,
        duration_sec: nil,
        bitrate_bps: nil
      }

      assert is_nil(stream.codec_profile)
      assert is_nil(stream.duration_sec)
      assert is_nil(stream.bitrate_bps)
    end
  end

  describe "Stream struct - video-specific fields" do
    test "stores video dimensions" do
      stream = %Stream{
        index: 0,
        type: :video,
        codec_name: "h264",
        timebase: {1, 90000},
        width: 1920,
        height: 1080
      }

      assert stream.width == 1920
      assert stream.height == 1080
    end

    test "stores frame rate as tuple" do
      stream = %Stream{
        index: 0,
        type: :video,
        codec_name: "h264",
        timebase: {1, 90000},
        frame_rate: {30, 1}
      }

      assert stream.frame_rate == {30, 1}
    end

    test "stores fractional frame rates" do
      stream = %Stream{
        index: 0,
        type: :video,
        codec_name: "h264",
        timebase: {1, 90000},
        frame_rate: {30000, 1001}
      }

      assert stream.frame_rate == {30000, 1001}
    end

    test "stores pixel format and color information" do
      stream = %Stream{
        index: 0,
        type: :video,
        codec_name: "h264",
        timebase: {1, 90000},
        pixel_format: "yuv420p",
        color_space: "bt709",
        color_range: "tv"
      }

      assert stream.pixel_format == "yuv420p"
      assert stream.color_space == "bt709"
      assert stream.color_range == "tv"
    end

    test "video fields are nil for audio streams" do
      stream = %Stream{
        index: 0,
        type: :audio,
        codec_name: "aac",
        timebase: {1, 48000}
      }

      assert is_nil(stream.width)
      assert is_nil(stream.height)
      assert is_nil(stream.frame_rate)
      assert is_nil(stream.pixel_format)
    end
  end

  describe "Stream struct - audio-specific fields" do
    test "stores audio sample rate and channels" do
      stream = %Stream{
        index: 0,
        type: :audio,
        codec_name: "aac",
        timebase: {1, 48000},
        sample_rate: 48000,
        channels: 2,
        channel_layout: "stereo"
      }

      assert stream.sample_rate == 48000
      assert stream.channels == 2
      assert stream.channel_layout == "stereo"
    end

    test "supports various channel layouts" do
      for {channels, layout} <- [{1, "mono"}, {2, "stereo"}, {6, "5.1"}, {8, "7.1"}] do
        stream = %Stream{
          index: 0,
          type: :audio,
          codec_name: "aac",
          timebase: {1, 48000},
          channels: channels,
          channel_layout: layout
        }

        assert stream.channels == channels
        assert stream.channel_layout == layout
      end
    end

    test "audio fields are nil for video streams" do
      stream = %Stream{
        index: 0,
        type: :video,
        codec_name: "h264",
        timebase: {1, 90000}
      }

      assert is_nil(stream.sample_rate)
      assert is_nil(stream.channels)
      assert is_nil(stream.channel_layout)
    end
  end

  describe "Stream.video?/1" do
    test "returns true for valid video stream" do
      stream = %Stream{
        index: 0,
        type: :video,
        codec_name: "h264",
        timebase: {1, 90000},
        width: 1920,
        height: 1080
      }

      assert Stream.video?(stream) == true
    end

    test "returns false for video stream without dimensions" do
      stream = %Stream{
        index: 0,
        type: :video,
        codec_name: "h264",
        timebase: {1, 90000}
      }

      refute Stream.video?(stream)
    end

    test "returns false for audio stream" do
      stream = %Stream{
        index: 0,
        type: :audio,
        codec_name: "aac",
        timebase: {1, 48000}
      }

      refute Stream.video?(stream)
    end
  end

  describe "Stream.audio?/1" do
    test "returns true for valid audio stream" do
      stream = %Stream{
        index: 0,
        type: :audio,
        codec_name: "aac",
        timebase: {1, 48000},
        sample_rate: 48000
      }

      assert Stream.audio?(stream) == true
    end

    test "returns false for audio stream without sample rate" do
      stream = %Stream{
        index: 0,
        type: :audio,
        codec_name: "aac",
        timebase: {1, 48000}
      }

      refute Stream.audio?(stream)
    end

    test "returns false for video stream" do
      stream = %Stream{
        index: 0,
        type: :video,
        codec_name: "h264",
        timebase: {1, 90000}
      }

      refute Stream.audio?(stream)
    end
  end

  describe "Stream.fps/1" do
    test "calculates FPS from frame_rate tuple" do
      stream = %Stream{
        index: 0,
        type: :video,
        codec_name: "h264",
        timebase: {1, 90000},
        frame_rate: {30, 1}
      }

      assert Stream.fps(stream) == 30.0
    end

    test "handles fractional frame rates (29.97fps)" do
      stream = %Stream{
        index: 0,
        type: :video,
        codec_name: "h264",
        timebase: {1, 90000},
        frame_rate: {30000, 1001}
      }

      fps = Stream.fps(stream)
      assert_in_delta fps, 29.97, 0.01
    end

    test "returns nil when frame_rate not set" do
      stream = %Stream{
        index: 0,
        type: :video,
        codec_name: "h264",
        timebase: {1, 90000}
      }

      assert Stream.fps(stream) == nil
    end
  end

  describe "Stream.resolution/1" do
    test "formats resolution as WIDTHxHEIGHT string" do
      stream = %Stream{
        index: 0,
        type: :video,
        codec_name: "h264",
        timebase: {1, 90000},
        width: 1920,
        height: 1080
      }

      assert Stream.resolution(stream) == "1920x1080"
    end

    test "handles various resolutions" do
      resolutions = [
        {3840, 2160, "3840x2160"},
        {1280, 720, "1280x720"},
        {640, 480, "640x480"}
      ]

      for {w, h, expected} <- resolutions do
        stream = %Stream{
          index: 0,
          type: :video,
          codec_name: "h264",
          timebase: {1, 90000},
          width: w,
          height: h
        }

        assert Stream.resolution(stream) == expected
      end
    end

    test "returns nil when dimensions not set" do
      stream = %Stream{
        index: 0,
        type: :video,
        codec_name: "h264",
        timebase: {1, 90000}
      }

      assert Stream.resolution(stream) == nil
    end
  end

  describe "MediaSchema.video_streams/1" do
    test "returns all video streams" do
      schema = build_multi_stream_schema()

      video_streams = MediaSchema.video_streams(schema)

      assert length(video_streams) == 1
      assert hd(video_streams).type == :video
      assert hd(video_streams).codec_name == "h264"
    end

    test "returns empty list when no video streams" do
      schema = %MediaSchema{
        file_path: "/tmp/audio.m4a",
        format: build_format(),
        streams: [
          %Stream{index: 0, type: :audio, codec_name: "aac", timebase: {1, 48000}}
        ],
        analyzed_at: DateTime.utc_now()
      }

      assert MediaSchema.video_streams(schema) == []
    end
  end

  describe "MediaSchema.audio_streams/1" do
    test "returns all audio streams" do
      schema = build_multi_stream_schema()

      audio_streams = MediaSchema.audio_streams(schema)

      assert length(audio_streams) == 2
      assert Enum.all?(audio_streams, &(&1.type == :audio))
    end

    test "returns empty list when no audio streams" do
      schema = %MediaSchema{
        file_path: "/tmp/silent.mp4",
        format: build_format(),
        streams: [
          %Stream{
            index: 0,
            type: :video,
            codec_name: "h264",
            timebase: {1, 90000}
          }
        ],
        analyzed_at: DateTime.utc_now()
      }

      assert MediaSchema.audio_streams(schema) == []
    end
  end

  describe "MediaSchema.primary_video_stream/1" do
    test "returns first video stream" do
      schema = build_multi_stream_schema()

      primary = MediaSchema.primary_video_stream(schema)

      assert primary.type == :video
      assert primary.index == 0
    end

    test "returns nil when no video streams" do
      schema = %MediaSchema{
        file_path: "/tmp/audio.m4a",
        format: build_format(),
        streams: [
          %Stream{index: 0, type: :audio, codec_name: "aac", timebase: {1, 48000}}
        ],
        analyzed_at: DateTime.utc_now()
      }

      assert MediaSchema.primary_video_stream(schema) == nil
    end
  end

  describe "MediaSchema.primary_audio_stream/1" do
    test "returns first audio stream" do
      schema = build_multi_stream_schema()

      primary = MediaSchema.primary_audio_stream(schema)

      assert primary.type == :audio
      assert primary.index == 1
      assert primary.codec_name == "aac"
    end

    test "returns nil when no audio streams" do
      schema = %MediaSchema{
        file_path: "/tmp/silent.mp4",
        format: build_format(),
        streams: [
          %Stream{index: 0, type: :video, codec_name: "h264", timebase: {1, 90000}}
        ],
        analyzed_at: DateTime.utc_now()
      }

      assert MediaSchema.primary_audio_stream(schema) == nil
    end
  end

  describe "MediaSchema.total_stream_bitrate/1" do
    test "sums bitrates from all streams" do
      schema = %MediaSchema{
        file_path: "/tmp/test.mp4",
        format: %Format{
          container_type: "mp4",
          duration_sec: 60.0,
          size_bytes: 10_000_000,
          bitrate_bps: 1_333_333
        },
        streams: [
          %Stream{
            index: 0,
            type: :video,
            codec_name: "h264",
            timebase: {1, 90000},
            bitrate_bps: 1_000_000
          },
          %Stream{
            index: 1,
            type: :audio,
            codec_name: "aac",
            timebase: {1, 48000},
            bitrate_bps: 128_000
          }
        ],
        analyzed_at: DateTime.utc_now()
      }

      assert MediaSchema.total_stream_bitrate(schema) == 1_128_000
    end

    test "falls back to format bitrate when stream bitrates unavailable" do
      schema = %MediaSchema{
        file_path: "/tmp/test.mp4",
        format: %Format{
          container_type: "mp4",
          duration_sec: 60.0,
          size_bytes: 10_000_000,
          bitrate_bps: 1_333_333
        },
        streams: [
          %Stream{
            index: 0,
            type: :video,
            codec_name: "h264",
            timebase: {1, 90000}
          }
        ],
        analyzed_at: DateTime.utc_now()
      }

      assert MediaSchema.total_stream_bitrate(schema) == 1_333_333
    end

    test "ignores nil bitrates when summing" do
      schema = %MediaSchema{
        file_path: "/tmp/test.mp4",
        format: %Format{
          container_type: "mp4",
          duration_sec: 60.0,
          size_bytes: 10_000_000,
          bitrate_bps: 1_333_333
        },
        streams: [
          %Stream{
            index: 0,
            type: :video,
            codec_name: "h264",
            timebase: {1, 90000},
            bitrate_bps: 1_000_000
          },
          %Stream{
            index: 1,
            type: :audio,
            codec_name: "aac",
            timebase: {1, 48000},
            bitrate_bps: nil
          }
        ],
        analyzed_at: DateTime.utc_now()
      }

      assert MediaSchema.total_stream_bitrate(schema) == 1_000_000
    end
  end

  # Test helpers
  defp build_format do
    %Format{
      container_type: "mov,mp4",
      duration_sec: 120.0,
      size_bytes: 10_000_000,
      bitrate_bps: 666_666
    }
  end

  defp build_multi_stream_schema do
    %MediaSchema{
      file_path: "/tmp/multi.mp4",
      format: build_format(),
      streams: [
        %Stream{
          index: 0,
          type: :video,
          codec_name: "h264",
          timebase: {1, 90000},
          bitrate_bps: 500_000
        },
        %Stream{
          index: 1,
          type: :audio,
          codec_name: "aac",
          timebase: {1, 48000},
          bitrate_bps: 128_000
        },
        %Stream{
          index: 2,
          type: :audio,
          codec_name: "aac",
          timebase: {1, 48000},
          bitrate_bps: 128_000
        }
      ],
      analyzed_at: DateTime.utc_now()
    }
  end
end
