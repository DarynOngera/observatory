defmodule Observatory.GOPStatsSchema do
  @moduledoc """
  GOP (Group of Pictures) analysis results.

  Provides frame-level statistics about video structure, particularly:
  - GOP boundaries and sizes
  - Keyframe (I-frame) positions
  - Frame type distribution (I/P/B)
  - Seekability metrics
  """

  alias __MODULE__.{GOP, AggregateStats}

  @type t :: %__MODULE__{
          media_file: String.t(),
          video_stream_index: non_neg_integer(),
          total_frames: non_neg_integer(),
          gops: [GOP.t()],
          keyframe_positions: [{float(), non_neg_integer()}],
          stats: AggregateStats.t()
        }

  defstruct [
    :media_file,
    :video_stream_index,
    :total_frames,
    :gops,
    :keyframe_positions,
    :stats
  ]

  defmodule GOP do
    @moduledoc """
    Single GOP (Group of Pictures) information.

    A GOP is a sequence of frames between two I-frames (keyframes).
    The first frame is always an I-frame.

      
    The compression ratio represents how much the video is compressed:

      compression_ratio = uncompressed_size / compressed_size

    For YUV 4:2:0 video (most common):
      - Uncompressed size per frame = width * height * 1.5 bytes
      - Y plane: width * height bytes (full resolution)
      - U plane: (width/2) * (height/2) bytes (quarter resolution)
      - V plane: (width/2) * (height/2) bytes (quarter resolution)
      - Total: width * height * (1 + 0.25 + 0.25) = width * height * 1.5
    """

    @type t :: %__MODULE__{
            index: non_neg_integer(),
            start_frame: non_neg_integer(),
            end_frame: non_neg_integer(),
            start_pts_sec: float(),
            end_pts_sec: float(),
            duration_sec: float(),
            frame_count: non_neg_integer(),
            structure: [String.t()],
            total_bytes: non_neg_integer(),
            i_frame_bytes: non_neg_integer(),
            compression_ratio: float() | nil
          }

    defstruct [
      :index,
      :start_frame,
      :end_frame,
      :start_pts_sec,
      :end_pts_sec,
      :duration_sec,
      :frame_count,
      :structure,
      :total_bytes,
      :i_frame_bytes,
      :compression_ratio
    ]

    @doc """
    Returns the percentage of GOP size that is the I-frame.
    """
    @spec i_frame_overhead(t()) :: float()
    def i_frame_overhead(%__MODULE__{i_frame_bytes: i, total_bytes: total})
        when total > 0 do
      i / total * 100
    end

    def i_frame_overhead(_), do: 0.0

    @doc """
    Counts frames by type.
    Returns map with :i, :p, :b counts.
    """
    @spec frame_type_counts(t()) :: %{
            i: non_neg_integer(),
            p: non_neg_integer(),
            b: non_neg_integer()
          }
    def frame_type_counts(%__MODULE__{structure: structure}) do
      Enum.reduce(structure, %{i: 0, p: 0, b: 0}, fn type, acc ->
        case String.downcase(type) do
          "i" -> %{acc | i: acc.i + 1}
          "p" -> %{acc | p: acc.p + 1}
          "b" -> %{acc | b: acc.b + 1}
          _ -> acc
        end
      end)
    end

    @spec compression_ratio_str(t()) :: String.t()
    def compression_ratio_str(%__MODULE__{compression_ratio: ratio}) when is_float(ratio) do
      "#{Float.round(ratio, 1)}:1"
    end

    def compression_ratio_str(_), do: "N/A"
  end

  defmodule AggregateStats do
    @moduledoc """
    Summary statistics across all GOPs.
    """

    @type t :: %__MODULE__{
            total_gops: non_neg_integer(),
            avg_gop_size: float(),
            gop_size_variance: float(),
            avg_gop_duration_sec: float(),
            keyframe_interval_sec: float(),
            i_frame_ratio: float(),
            b_frame_ratio: float(),
            seekability_score: float()
          }

    defstruct [
      :total_gops,
      :avg_gop_size,
      :gop_size_variance,
      :avg_gop_duration_sec,
      :keyframe_interval_sec,
      :i_frame_ratio,
      :b_frame_ratio,
      :seekability_score
    ]
  end

  @doc """
  Calculates aggregate statistics from a list of GOPs.
  """
  @spec calculate_stats([GOP.t()], non_neg_integer()) :: AggregateStats.t()
  def calculate_stats(gops, total_frames) when length(gops) > 0 do
    total_gops = length(gops)

    gop_sizes = Enum.map(gops, & &1.frame_count)
    avg_gop_size = Enum.sum(gop_sizes) / total_gops
    gop_size_variance = calculate_variance(gop_sizes, avg_gop_size)

    gop_durations = Enum.map(gops, & &1.duration_sec)
    avg_gop_duration = Enum.sum(gop_durations) / total_gops

    keyframe_interval = avg_gop_duration

    all_frames = Enum.flat_map(gops, & &1.structure)
    i_frames = Enum.count(all_frames, &(String.downcase(&1) == "i"))
    b_frames = Enum.count(all_frames, &(String.downcase(&1) == "b"))

    i_frame_ratio = if total_frames > 0, do: i_frames / total_frames * 100, else: 0.0
    b_frame_ratio = if total_frames > 0, do: b_frames / total_frames * 100, else: 0.0

    # Seekability score (0-100)
    # Lower GOP size + lower variance = higher seekability
    seekability = calculate_seekability_score(avg_gop_size, gop_size_variance)

    %AggregateStats{
      total_gops: total_gops,
      avg_gop_size: avg_gop_size,
      gop_size_variance: gop_size_variance,
      avg_gop_duration_sec: avg_gop_duration,
      keyframe_interval_sec: keyframe_interval,
      i_frame_ratio: i_frame_ratio,
      b_frame_ratio: b_frame_ratio,
      seekability_score: seekability
    }
  end

  def calculate_stats([], _total_frames) do
    %AggregateStats{
      total_gops: 0,
      avg_gop_size: 0.0,
      gop_size_variance: 0.0,
      avg_gop_duration_sec: 0.0,
      keyframe_interval_sec: 0.0,
      i_frame_ratio: 0.0,
      b_frame_ratio: 0.0,
      seekability_score: 0.0
    }
  end

  defp calculate_variance(values, mean) do
    sum_squared_diff =
      values
      |> Enum.map(fn v -> :math.pow(v - mean, 2) end)
      |> Enum.sum()

    sum_squared_diff / length(values)
  end

  defp calculate_seekability_score(avg_gop_size, variance) do
    # Perfect score: GOP size = 1 (every frame is a key frame)
    # Good score: GOP size < 30, low variance
    # Poor score: GOP size > 120, high variance

    size_penalty = min(avg_gop_size / 120 * 50, 50)
    variance_penalty = min(variance / 100 * 50, 50)

    max(100 - size_penalty - variance_penalty, 0.0)
  end
end
