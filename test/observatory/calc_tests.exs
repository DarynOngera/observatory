# test/observatory/gop_calculations_verification_test.exs
defmodule Observatory.GOPCalculationsVerificationTest do
  use ExUnit.Case, async: true

  alias Observatory.{GOPStatsSchema, FrameParser}
  alias Observatory.GOPStatsSchema.GOP

  describe "compression ratio calculation verification" do
    test "YUV 4:2:0 uncompressed size calculation is correct" do
      # For 1920x1080 YUV 4:2:0:
      # Y plane: 1920 * 1080 = 2,073,600 bytes
      # U plane: 960 * 540 = 518,400 bytes (1/4 of Y)
      # V plane: 960 * 540 = 518,400 bytes (1/4 of Y)
      # Total: 2,073,600 + 518,400 + 518,400 = 3,110,400 bytes per frame
      # OR: 1920 * 1080 * 1.5 = 3,110,400 bytes per frame

      width = 1920
      height = 1080
      expected_per_frame = width * height * 1.5

      assert expected_per_frame == 3_110_400

      # For 4 frames:
      expected_4_frames = expected_per_frame * 4
      assert expected_4_frames == 12_441_600
    end

    test "compression ratio with realistic H.264 GOP" do
      # Typical H.264 GOP at 1920x1080:
      # I-frame: ~150KB = 153,600 bytes
      # P-frame: ~15KB = 15,360 bytes
      # B-frame: ~5KB = 5,120 bytes
      # Pattern: I B B P B B P B B P B B (12 frames)

      frames_json = """
      {
        "frames": [
          {"pict_type": "I", "key_frame": 1, "pkt_pts_time": "0.000", "pkt_size": "153600"},
          {"pict_type": "B", "key_frame": 0, "pkt_pts_time": "0.033", "pkt_size": "5120"},
          {"pict_type": "B", "key_frame": 0, "pkt_pts_time": "0.067", "pkt_size": "5120"},
          {"pict_type": "P", "key_frame": 0, "pkt_pts_time": "0.100", "pkt_size": "15360"},
          {"pict_type": "B", "key_frame": 0, "pkt_pts_time": "0.133", "pkt_size": "5120"},
          {"pict_type": "B", "key_frame": 0, "pkt_pts_time": "0.167", "pkt_size": "5120"},
          {"pict_type": "P", "key_frame": 0, "pkt_pts_time": "0.200", "pkt_size": "15360"},
          {"pict_type": "B", "key_frame": 0, "pkt_pts_time": "0.233", "pkt_size": "5120"},
          {"pict_type": "B", "key_frame": 0, "pkt_pts_time": "0.267", "pkt_size": "5120"},
          {"pict_type": "P", "key_frame": 0, "pkt_pts_time": "0.300", "pkt_size": "15360"},
          {"pict_type": "B", "key_frame": 0, "pkt_pts_time": "0.333", "pkt_size": "5120"},
          {"pict_type": "B", "key_frame": 0, "pkt_pts_time": "0.367", "pkt_size": "5120"}
        ]
      }
      """

      dimensions = {1920, 1080}
      {:ok, gop_stats} = FrameParser.parse(frames_json, "test.mp4", 0, dimensions)

      gop = hd(gop_stats.gops)

      # Compressed size: 153,600 + (8 * 5,120) + (3 * 15,360) = 240,640 bytes
      expected_compressed = 153_600 + 8 * 5_120 + 3 * 15_360
      assert gop.total_bytes == expected_compressed

      # Uncompressed size: 1920 * 1080 * 1.5 * 12 = 37,324,800 bytes
      expected_uncompressed = 1920 * 1080 * 1.5 * 12

      # Compression ratio: 37,324,800 / 240,640 ≈ 155.1
      expected_ratio = expected_uncompressed / expected_compressed

      assert_in_delta gop.compression_ratio, expected_ratio, 0.1
      assert_in_delta gop.compression_ratio, 155.1, 0.5

      # Verify it's actually compressed
      assert gop.compression_ratio > 100
      assert gop.compression_ratio < 300
    end

    test "compression ratio without dimensions returns nil" do
      frames_json = """
      {
        "frames": [
          {"pict_type": "I", "key_frame": 1, "pkt_pts_time": "0.000", "pkt_size": "50000"}
        ]
      }
      """

      {:ok, gop_stats} = FrameParser.parse(frames_json, "test.mp4", 0, nil)

      gop = hd(gop_stats.gops)
      assert is_nil(gop.compression_ratio)
    end

    test "compression ratio for different resolutions" do
      test_cases = [
        {640, 480, "SD"},
        {1280, 720, "HD"},
        {1920, 1080, "Full HD"},
        {3840, 2160, "4K"}
      ]

      for {width, height, label} <- test_cases do
        frames_json = """
        {
          "frames": [
            {"pict_type": "I", "key_frame": 1, "pkt_pts_time": "0.000", "pkt_size": "50000"},
            {"pict_type": "P", "key_frame": 0, "pkt_pts_time": "0.033", "pkt_size": "10000"}
          ]
        }
        """

        {:ok, gop_stats} = FrameParser.parse(frames_json, "test.mp4", 0, {width, height})
        gop = hd(gop_stats.gops)

        uncompressed = width * height * 1.5 * 2
        compressed = 60_000
        expected_ratio = uncompressed / compressed

        assert_in_delta gop.compression_ratio,
                        expected_ratio,
                        0.1,
                        "#{label} (#{width}x#{height}) compression ratio mismatch"

        # Higher resolution should have higher compression ratio (more data to compress)
        assert gop.compression_ratio > 0
      end
    end
  end

  describe "I-frame overhead calculation verification" do
    test "I-frame overhead percentage is accurate" do
      gop = %GOP{
        index: 0,
        start_frame: 0,
        end_frame: 11,
        start_pts_sec: 0.0,
        end_pts_sec: 0.4,
        duration_sec: 0.4,
        frame_count: 12,
        structure: ["I", "B", "B", "P", "B", "B", "P", "B", "B", "P", "B", "B"],
        total_bytes: 100_000,
        i_frame_bytes: 30_000,
        compression_ratio: 150.0
      }

      overhead = GOP.i_frame_overhead(gop)

      # 30,000 / 100,000 * 100 = 30%
      assert overhead == 30.0

      # Verify it's a reasonable percentage
      assert overhead >= 0
      assert overhead <= 100
    end

    test "I-frame overhead for different GOP patterns" do
      test_cases = [
        # {i_frame_bytes, total_bytes, expected_percentage, description}
        {50_000, 100_000, 50.0, "I-frame is 50% of GOP"},
        {25_000, 100_000, 25.0, "I-frame is 25% of GOP (typical)"},
        {10_000, 100_000, 10.0, "I-frame is 10% of GOP (very efficient)"},
        {75_000, 100_000, 75.0, "I-frame is 75% of GOP (inefficient)"}
      ]

      for {i_bytes, total_bytes, expected_pct, desc} <- test_cases do
        gop = %GOP{
          index: 0,
          start_frame: 0,
          end_frame: 10,
          start_pts_sec: 0.0,
          end_pts_sec: 0.4,
          duration_sec: 0.4,
          frame_count: 10,
          structure: ["I", "P", "P", "P", "P", "P", "P", "P", "P", "P"],
          total_bytes: total_bytes,
          i_frame_bytes: i_bytes,
          compression_ratio: nil
        }

        assert GOP.i_frame_overhead(gop) == expected_pct, desc
      end
    end

    test "I-frame overhead with zero total returns 0" do
      gop = %GOP{
        index: 0,
        start_frame: 0,
        end_frame: 0,
        start_pts_sec: 0.0,
        end_pts_sec: 0.0,
        duration_sec: 0.0,
        frame_count: 1,
        structure: ["I"],
        total_bytes: 0,
        i_frame_bytes: 0,
        compression_ratio: nil
      }

      assert GOP.i_frame_overhead(gop) == 0.0
    end
  end

  describe "frame type counting verification" do
    test "counts I/P/B frames correctly" do
      test_cases = [
        {["I", "P", "P", "P"], %{i: 1, p: 3, b: 0}, "IPP pattern"},
        {["I", "B", "B", "P", "B", "B", "P"], %{i: 1, p: 2, b: 4}, "IBBPBBP pattern"},
        {["I"], %{i: 1, p: 0, b: 0}, "I-only"},
        {["I", "P", "B", "P", "B"], %{i: 1, p: 2, b: 2}, "Mixed pattern"}
      ]

      for {structure, expected_counts, desc} <- test_cases do
        gop = %GOP{
          index: 0,
          start_frame: 0,
          end_frame: length(structure) - 1,
          start_pts_sec: 0.0,
          end_pts_sec: 1.0,
          duration_sec: 1.0,
          frame_count: length(structure),
          structure: structure,
          total_bytes: 100_000,
          i_frame_bytes: 30_000,
          compression_ratio: nil
        }

        counts = GOP.frame_type_counts(gop)
        assert counts == expected_counts, desc
      end
    end

    test "handles case-insensitive frame types" do
      gop = %GOP{
        index: 0,
        start_frame: 0,
        end_frame: 5,
        start_pts_sec: 0.0,
        end_pts_sec: 0.2,
        duration_sec: 0.2,
        frame_count: 6,
        structure: ["I", "b", "B", "p", "P", "?"],
        total_bytes: 50_000,
        i_frame_bytes: 20_000,
        compression_ratio: nil
      }

      counts = GOP.frame_type_counts(gop)

      assert counts.i == 1
      assert counts.b == 2
      assert counts.p == 2
    end
  end

  describe "aggregate statistics verification" do
    test "calculates average GOP size correctly" do
      gops = [
        build_test_gop(0, 12),
        build_test_gop(1, 15),
        build_test_gop(2, 10),
        build_test_gop(3, 13)
      ]

      stats = GOPStatsSchema.calculate_stats(gops, 50)

      # Average: (12 + 15 + 10 + 13) / 4 = 12.5
      assert stats.avg_gop_size == 12.5
    end

    test "calculates GOP size variance correctly" do
      # Variance = Σ(x - μ)² / n
      # Values: [10, 12, 14, 16]
      # Mean: 13
      # Variance: ((10-13)² + (12-13)² + (14-13)² + (16-13)²) / 4
      #         = (9 + 1 + 1 + 9) / 4 = 5

      gops = [
        build_test_gop(0, 10),
        build_test_gop(1, 12),
        build_test_gop(2, 14),
        build_test_gop(3, 16)
      ]

      stats = GOPStatsSchema.calculate_stats(gops, 52)

      assert stats.avg_gop_size == 13.0
      assert stats.gop_size_variance == 5.0
    end

    test "calculates frame ratios correctly" do
      # 4 GOPs, each with structure: I B B P (4 frames)
      # Total: 4 I-frames, 8 B-frames, 4 P-frames = 16 frames
      # I-frame ratio: 4/16 * 100 = 25%
      # B-frame ratio: 8/16 * 100 = 50%

      gops = [
        build_test_gop(0, 4, ["I", "B", "B", "P"]),
        build_test_gop(1, 4, ["I", "B", "B", "P"]),
        build_test_gop(2, 4, ["I", "B", "B", "P"]),
        build_test_gop(3, 4, ["I", "B", "B", "P"])
      ]

      stats = GOPStatsSchema.calculate_stats(gops, 16)

      assert stats.i_frame_ratio == 25.0
      assert stats.b_frame_ratio == 50.0
    end

    test "calculates keyframe interval correctly" do
      # Each GOP lasts 0.5 seconds
      gops = [
        build_test_gop(0, 15, ["I"] ++ List.duplicate("P", 14), 0.0, 0.5),
        build_test_gop(1, 15, ["I"] ++ List.duplicate("P", 14), 0.5, 1.0),
        build_test_gop(2, 15, ["I"] ++ List.duplicate("P", 14), 1.0, 1.5)
      ]

      stats = GOPStatsSchema.calculate_stats(gops, 45)

      assert stats.keyframe_interval_sec == 0.5
      assert stats.avg_gop_duration_sec == 0.5
    end
  end

  describe "seekability score verification" do
    test "perfect seekability (GOP size = 1)" do
      # Every frame is a keyframe
      gops = List.duplicate(build_test_gop(0, 1, ["I"]), 100)

      stats = GOPStatsSchema.calculate_stats(gops, 100)

      # Score should be very high (close to 100)
      assert stats.seekability_score > 95.0
      assert stats.seekability_score <= 100.0
    end

    test "good seekability (GOP size < 30, low variance)" do
      # GOP size 15, variance ~1
      gops = [
        build_test_gop(0, 15),
        build_test_gop(1, 14),
        build_test_gop(2, 16),
        build_test_gop(3, 15)
      ]

      stats = GOPStatsSchema.calculate_stats(gops, 60)

      # avg = 15, variance = 0.5
      # size_penalty = 15/120 * 50 = 6.25
      # variance_penalty = 0.5/100 * 50 = 0.25
      # score = 100 - 6.25 - 0.25 = 93.5

      assert stats.seekability_score > 90.0
    end

    test "poor seekability (GOP size > 120, high variance)" do
      # Large, inconsistent GOPs
      gops = [
        build_test_gop(0, 150),
        build_test_gop(1, 100),
        build_test_gop(2, 200),
        build_test_gop(3, 180)
      ]

      stats = GOPStatsSchema.calculate_stats(gops, 630)

      # avg = 157.5, variance = 1743.75
      # Both penalties will be capped at 50
      # score = 100 - 50 - 50 = 0

      assert stats.seekability_score == 0.0
    end

    test "moderate seekability (GOP size 60, moderate variance)" do
      gops = [
        build_test_gop(0, 60),
        build_test_gop(1, 50),
        build_test_gop(2, 70),
        build_test_gop(3, 60)
      ]

      stats = GOPStatsSchema.calculate_stats(gops, 240)

      # avg = 60, variance = 50
      # size_penalty = 60/120 * 50 = 25
      # variance_penalty = 50/100 * 50 = 25
      # score = 100 - 25 - 25 = 50

      assert_in_delta stats.seekability_score, 50.0, 1.0
    end
  end

  describe "edge cases and boundary conditions" do
    test "handles empty GOP list" do
      stats = GOPStatsSchema.calculate_stats([], 0)

      assert stats.total_gops == 0
      assert stats.avg_gop_size == 0.0
      assert stats.gop_size_variance == 0.0
      assert stats.seekability_score == 0.0
    end

    test "handles single GOP" do
      gops = [build_test_gop(0, 30)]

      stats = GOPStatsSchema.calculate_stats(gops, 30)

      assert stats.total_gops == 1
      assert stats.avg_gop_size == 30.0
      # No variance with single value
      assert stats.gop_size_variance == 0.0
    end

    test "handles very large compression ratios" do
      # Ultra high quality, low compression
      frames_json = """
      {
        "frames": [
          {"pict_type": "I", "key_frame": 1, "pkt_pts_time": "0.000", "pkt_size": "3000000"}
        ]
      }
      """

      {:ok, gop_stats} = FrameParser.parse(frames_json, "test.mp4", 0, {1920, 1080})
      gop = hd(gop_stats.gops)

      # Uncompressed: 3,110,400 bytes
      # Compressed: 3,000,000 bytes
      # Ratio: ~1.04 (barely compressed)

      assert gop.compression_ratio > 1.0
      assert gop.compression_ratio < 2.0
    end

    test "handles very small compression ratios (highly compressed)" do
      # Extremely compressed
      frames_json = """
      {
        "frames": [
          {"pict_type": "I", "key_frame": 1, "pkt_pts_time": "0.000", "pkt_size": "1000"}
        ]
      }
      """

      {:ok, gop_stats} = FrameParser.parse(frames_json, "test.mp4", 0, {1920, 1080})
      gop = hd(gop_stats.gops)

      # Uncompressed: 3,110,400 bytes
      # Compressed: 1,000 bytes
      # Ratio: ~3,110

      assert gop.compression_ratio > 3000.0
    end
  end

  # Helper functions

  defp build_test_gop(index, frame_count, structure \\ nil, start_sec \\ 0.0, end_sec \\ 1.0) do
    actual_structure = structure || ["I"] ++ List.duplicate("P", frame_count - 1)

    %GOP{
      index: index,
      start_frame: index * frame_count,
      end_frame: (index + 1) * frame_count - 1,
      start_pts_sec: start_sec,
      end_pts_sec: end_sec,
      duration_sec: end_sec - start_sec,
      frame_count: frame_count,
      structure: actual_structure,
      total_bytes: frame_count * 10_000,
      i_frame_bytes: 30_000,
      compression_ratio: nil
    }
  end
end
