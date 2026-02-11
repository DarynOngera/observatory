defmodule Observatory.MediaSchema do
  @moduledoc """
    Normalized representation of media file structure
    (Normalize ffmpeg output)
  """

  alias __MODULE__.{Format, Stream}

  @type t :: %__MODULE__{
          file_path: String.t(),
          format: Format.t(),
          streams: [Stream.t()],
          analyzed_at: DateTime.t()
        }
  # @enforce_keys [:file_path, :format, :streams, :analyzed_at]
  defstruct [
    :file_path,
    :format,
    :streams,
    :analyzed_at
  ]

  defmodule Format do
    @type t :: %__MODULE__{
            container_type: String.t(),
            duration_sec: float(),
            size_bytes: non_neg_integer(),
            bitrate_bps: non_neg_integer(),
            metadata: map()
          }

    # @enforce_keys [:container_type, :duration_sec, :size_bytes, :bitrate_bps]
    defstruct [
      :container_type,
      :duration_sec,
      :size_bytes,
      :bitrate_bps,
      metadata: %{}
    ]
  end

  defmodule Stream do
    @type stream_type :: :video | :audio | :subtitle | :uknown

    @type t :: %__MODULE__{
            index: non_neg_integer(),
            type: stream_type(),
            codec_name: String.t(),
            codec_profile: String.t(),
            timebase: {pos_integer(), pos_integer()},
            duration_sec: float(),
            bitrate_bps: non_neg_integer() | nil,
            # Video specific
            width: pos_integer() | nil,
            height: pos_integer() | nil,
            frame_rate: {pos_integer(), pos_integer()} | nil,
            pixel_format: String.t() | nil,
            color_space: String.t() | nil,
            color_range: String.t() | nil,
            # Audio specific
            sample_rate: pos_integer() | nil,
            channels: pos_integer() | nil,
            channel_layout: String.t() | nil
          }

    # @enforce_keys [:index, :type, :codec_name, :timebase]
    defstruct [
      :index,
      :type,
      :codec_name,
      :codec_profile,
      :timebase,
      :duration_sec,
      :bitrate_bps,
      # Video
      :width,
      :height,
      :frame_rate,
      :pixel_format,
      :color_space,
      :color_range,
      # Audio
      :sample_rate,
      :channels,
      :channel_layout
    ]

    @doc """
    Returns true of this is a video stream with valid dimensions
    """
    @spec video?(t()) :: boolean()
    def video?(%__MODULE__{type: :video, width: w, height: h})
        when is_integer(w) and is_integer(h) and w > 0 and h > 0 do
      true
    end

    def video?(%__MODULE__{}), do: false

    @doc """
    Returns true if this is an audio stream.
    """
    @spec audio?(t()) :: boolean()
    def audio?(%__MODULE__{type: :audio, sample_rate: sr})
        when is_integer(sr) and sr > 0 do
      true
    end

    def audio?(%__MODULE__{}), do: false

    @doc """
    Calculates frames per second from frame_rate tuple.
    Returns nil if frame_rate is not set.

    ## Examples

        iex> stream = %Stream{frame_rate: {30, 1}, ...}
        iex> Stream.fps(stream)
        30.0
        
        iex> stream = %Stream{frame_rate: {30000, 1001}}
        iex> Stream.fps(stream)
        29.97002997002997
    """
    @spec fps(t()) :: float() | nil
    def fps(%__MODULE__{frame_rate: {num, den}}) when den > 0 do
      num / den
    end

    def fps(_), do: nil

    @doc """
    Calculates resolution as "WIDTHxHEIGHT" string.
    Returns nil if width or height not set.

    ## Examples

        iex> stream = %Stream{width: 1920, height: 1080}
        iex> Stream.resolution(stream)
        "1920x1080"
    """
    @spec resolution(t()) :: String.t() | nil
    def resolution(%__MODULE__{width: w, height: h})
        when is_integer(w) and is_integer(h) do
      "#{w}x#{h}"
    end

    def resolution(_), do: nil
  end

  @doc """
  Returns all video streams from the schema.
  """
  @spec video_streams(t()) :: [Stream.t()]
  def video_streams(%__MODULE__{streams: streams}) do
    Enum.filter(streams, &(&1.type == :video))
  end

  @doc """
  Returns all audio streams from the schema.
  """
  @spec audio_streams(t()) :: [Stream.t()]
  def audio_streams(%__MODULE__{streams: streams}) do
    Enum.filter(streams, &(&1.type == :audio))
  end

  @doc """
  Returns the primary video stream (first video stream).
  Returns nil if no video streams exist.
  """
  @spec primary_video_stream(t()) :: Stream.t() | nil
  def primary_video_stream(schema) do
    schema
    |> video_streams()
    |> List.first()
  end

  @doc """
  Returns the primary audio stream (first audio stream).
  Returns nil if no audio streams exist.
  """
  @spec primary_audio_stream(t()) :: Stream.t() | nil
  def primary_audio_stream(schema) do
    schema
    |> audio_streams()
    |> List.first()
  end

  @doc """
  Calculates the total bitrate of all streams.
  Falls back to format bitrate if stream bitrates are unavailable.
  """
  @spec total_stream_bitrate(t()) :: non_neg_integer()
  def total_stream_bitrate(%__MODULE__{streams: streams, format: format}) do
    stream_sum =
      streams
      |> Enum.map(& &1.bitrate_bps)
      |> Enum.reject(&is_nil/1)
      |> Enum.sum()

    if stream_sum > 0 do
      stream_sum
    else
      format.bitrate_bps
    end
  end
end
