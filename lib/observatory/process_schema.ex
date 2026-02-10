defmodule Observatory.ProcessSchema do 
   @moduledoc """
  Captures the transformation process metadata and events.
  
  Tracks FFmpeg encoding progress, events, and metrics in real-time.
  """
  
  alias __MODULE__.{TransformConfig, ProcessEvent, ProcessStats}

  @type t :: %__MODULE__{
    input_file: String.t(),
    output_file: String.t(),
    config: TransformConfig.t(),
    started_at: DateTime.t(),
    completed_at: DateTime.t() | nil,
    status: status(),
    events: [ProcessEvent.t()],
    stats: ProcessStats.t() | nil,
    error: String.t() | nil
  }

  @type status :: :pending | :running | :completed | :failed

  defstruct [
    :input_file,
    :output_file,
    :config,
    :started_at,
    :completed_at,
    :status,
    :events,
    :stats,
    :error
  ]

  defmodule TransformConfig do
    @moduledoc """
    Configuration for media transformation.
    """
    
    @type t :: %__MODULE__{
      codec: String.t(),
      container: String.t(),
      video_bitrate: pos_integer() | nil,
      audio_bitrate: pos_integer() | nil,
      resolution: {pos_integer(), pos_integer()} | nil,
      frame_rate: {pos_integer(), pos_integer()} | nil,
      gop_size: pos_integer() | nil,
      preset: atom() | String.t() | nil,
      crf: pos_integer() | nil,
      extra_params: map()
    }

    defstruct [
      :codec,
      :container,
      :video_bitrate,
      :audio_bitrate,
      :resolution,
      :frame_rate,
      :gop_size,
      :preset,
      :crf,
      extra_params: %{}
    ]
  end

  defmodule ProcessEvent do
    @moduledoc """
    Individual event during transformation process.
    """

    @type event_type :: :started | :progress | :warning | :error | :completed
    
    @type t :: %__MODULE__{
      timestamp: DateTime.t(),
      type: event_type(),
      message: String.t(),
      data: map()
     }

    defstruct [
      :timestamp,
      :type,
      :message,
      data: %{}
    ]
  end

  defmodule ProcessStats do
    @moduledoc """
    Aggregate statistics from transformation process.
    """

    @type t :: %__MODULE__{
      duration_sec: float(),
      frames_processed: non_neg_integer(),
      fps: float(),
      bitrate_kbps: float(),
      speed: float(),
      size_bytes: non_neg_integer(),
      quality_score: float() | nil
     }

    defstruct [
      :duration_sec,
      :frames_processed,
      :fps,
      :bitrate_kbps,
      :speed,
      :size_bytes,
      :quality_score
    ]
  end

  @doc """
  Creates a new process schema.
  """
  @spec new(String.t(), String.t(), TransformConfig.t()) :: t()
  def new(input_file, output_file, config) do
    %__MODULE__{
      input_file: input_file,
      output_file: output_file,
      config: config,
      started_at: DateTime.utc_now(),
      completed_at: nil,
      status: :pending,
      events: [],
      stats: nil,
      error: nil
    }
  end

  @doc """
  Adds an event to the process.
  """
  @spec add_event(t(), ProcessEvent.t()) :: t()
  def add_event(%__MODULE__{events: events} = process, event) do
    %{process | events: events ++ [event]}
  end

  @doc """
  Marks process as running.
  """
  @spec mark_running(t()) :: t()
  def mark_running(process) do
    event = %ProcessEvent{
      timestamp: DateTime.utc_now(),
      type: :started,
      message: "Transformation started"
    }

    process
    |> add_event(event)
    |> Map.put(:status, :running)
  end

  @doc """
  Marks process as completed with stats.
  """
  @spec mark_completed(t(), ProcessStats.t()) :: t()
  def mark_completed(process, stats) do
    event = %ProcessEvent{
      timestamp: DateTime.utc_now(),
      type: :completed,
      message: "Transformation completed"
    }

    process
    |> add_event(event)
    |> Map.put(:status, :completed)
    |> Map.put(:completed_at, DateTime.utc_now())
    |> Map.put(:stats, stats)
  end

  @doc """
  Marks process as failed.
  """
  @spec mark_failed(t(), String.t()) :: t()
  def mark_failed(process, error) do
    event = %ProcessEvent{
      timestamp: DateTime.utc_now(),
      type: :error,
      message: "Transformation failed: #{error}"
    }

    process
    |> add_event(event)
    |> Map.put(:status, :failed)
    |> Map.put(:completed_at, DateTime.utc_now())
    |> Map.put(:error, error)
  end

  @doc """
  Adds a progress event.
  """
  @spec add_progress(t(), map()) :: t()
  def add_progress(process, progress_data) do
    event = %ProcessEvent{
      timestamp: DateTime.utc_now(),
      type: :progress,
      message: "Processing frame #{progress_data[:frame] || 0}",
      data: progress_data
    }

    add_event(process, event)
  end
end
