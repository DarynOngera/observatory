defmodule Observatory.Membrane.TransformPipeline do
  @moduledoc """
  Membrane pipeline for media transformation with observable events.
  
  This pipeline:
  1. Reads input file
  2. Demuxes streams
  3. Optionally transcodes video/audio
  4. Muxes to output container
  5. Emits telemetry events for progress tracking
  """

  use Membrane.Pipeline
  import Membrane.ChildrenSpec

  require Membrane.Logger

  alias Membrane.{File, MP4, H264, AAC}
  alias Observatory.ProcessSchema

  @impl true
  def handle_init(_ctx, opts) do
    input_file = opts[:input_file]
    output_file = opts[:output_file]
    config = opts[:config]
    callback_pid = opts[:callback_pid]

    spec = build_pipeline_spec(input_file, output_file, config)

    state = %{
      input_file: input_file,
      output_file: output_file,
      config: config,
      callback_pid: callback_pid,
      started_at: DateTime.utc_now(),
      frames_processed: 0,
      eos_received: %{}
    }

    {[spec: spec], state}
  end

  @impl true
  def handle_element_end_of_stream(:output_sink, _pad, _ctx, state) do
    # All streams completed
    send_completion_event(state)
    {[terminate: :normal], state}
  end

  @impl true
  def handle_element_end_of_stream(element, _pad, _ctx, state) do
    # Track individual stream completion
    eos_received = Map.put(state.eos_received, element, true)
    {[], %{state | eos_received: eos_received}}
  end

  @impl true
  def handle_info({:frame_processed, _metadata}, _ctx, state) do
    # Track progress
    new_state = %{state | frames_processed: state.frames_processed + 1}
    
    # Send progress every 10 frames
    if rem(new_state.frames_processed, 10) == 0 do
      send_progress_event(new_state)
    end

    {[], new_state}
  end

  # Private functions

  defp build_pipeline_spec(input_file, output_file, _config) do
    child(:input_file, %File.Source{location: input_file})
    |> child(:demuxer, MP4.Demuxer.ISOM)
    |> via_in(:input)
    |> child(:muxer, MP4.Muxer.ISOM)
    |> child(:output_file, %File.Sink{location: output_file})
  end

  defp send_progress_event(state) do
    if state.callback_pid do
      event = %ProcessSchema.ProcessEvent{
        timestamp: DateTime.utc_now(),
        type: :progress,
        message: "Processed #{state.frames_processed} frames",
        data: %{
          frames_processed: state.frames_processed
        }
      }

      send(state.callback_pid, {:membrane_event, :progress, event})
    end
  end

  defp send_completion_event(state) do
    if state.callback_pid do
      duration = DateTime.diff(DateTime.utc_now(), state.started_at, :millisecond) / 1000

      event = %ProcessSchema.ProcessEvent{
        timestamp: DateTime.utc_now(),
        type: :completed,
        message: "Pipeline completed",
        data: %{
          frames_processed: state.frames_processed,
          duration_sec: duration
        }
      }

      send(state.callback_pid, {:membrane_event, :completed, event})
    end
  end
end
