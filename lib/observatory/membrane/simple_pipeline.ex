defmodule Observatory.Membrane.SimplePipeline do
  use Membrane.Pipeline
  require Membrane.Logger

  alias Membrane.{File, MP4}
  alias Observatory.ProcessSchema

  @impl true
  def handle_init(_ctx, opts) do
    input_file = Keyword.fetch!(opts, :input_file)
    output_file = Keyword.fetch!(opts, :output_file)
    callback_pid = Keyword.get(opts, :callback_pid)

    Membrane.Logger.info("Simple pipeline starting: #{input_file} -> #{output_file}")

    spec = [
      child(:input, %File.Source{location: input_file})
      |> child(:demuxer, MP4.Demuxer.ISOM),
      child(:muxer, MP4.Muxer.ISOM)
      |> child(:output, %File.Sink{location: output_file})
    ]

    state = %{
      input_file: input_file,
      output_file: output_file,
      callback_pid: callback_pid,
      started_at: DateTime.utc_now(),
      stream_count: 0,
      completed_streams: 0,
      muxer_finished: false,
      output_finished: false,
      completion_sent: false
    }

    {[spec: spec], state}
  end

  @impl true
  def handle_child_notification({:new_stream, track_id, stream_format}, :demuxer, _ctx, state) do
    Membrane.Logger.info("New stream: track_id: #{track_id}, format=#{inspect(stream_format)}")

    spec = [
      get_child(:demuxer)
      |> via_out(Pad.ref(:output, track_id))
      |> via_in(Pad.ref(:input, track_id), options: [track_id: track_id])
      |> get_child(:muxer)
    ]

    new_state = %{state | stream_count: state.stream_count + 1}
    {[spec: spec], new_state}
  end

  @impl true
  def handle_element_end_of_stream(:output, pad, _ctx, state) do
    Membrane.Logger.info("Output sink finished on pad #{inspect(pad)}")
    new_state = %{state | output_finished: true}
    maybe_complete(new_state)
  end

  @impl true
  def handle_element_end_of_stream(:muxer, pad, _ctx, state) do
    Membrane.Logger.info("Muxer finished on pad #{inspect(pad)}")
    new_state = %{state | muxer_finished: true}
    maybe_complete(new_state)
  end

  @impl true
  def handle_element_end_of_stream(:demuxer, pad, _ctx, state) do
    completed = state.completed_streams + 1

    Membrane.Logger.info(
      "Demuxer output finished on pad #{inspect(pad)} (#{completed}/#{state.stream_count})"
    )

    {[], %{state | completed_streams: completed}}
  end

  @impl true
  def handle_element_end_of_stream(element, pad, _ctx, state) do
    Membrane.Logger.info("Element #{inspect(element)} finished on pad #{inspect(pad)}")
    {[], state}
  end

  defp maybe_complete(state) do
    if state.muxer_finished && state.output_finished && !state.completion_sent do
      Membrane.Logger.info("All elements finished - completing pipeline")
      send_completion_event(state)
      {[terminate: :normal], %{state | completion_sent: true}}
    else
      {[], state}
    end
  end

  defp send_completion_event(state) do
    if state.callback_pid do
      duration = DateTime.diff(DateTime.utc_now(), state.started_at, :millisecond) / 1000

      event = %ProcessSchema.ProcessEvent{
        timestamp: DateTime.utc_now(),
        type: :completed,
        message: "Simple pipeline completed",
        data: %{
          duration_sec: duration,
          pipeline_pid: self()
        }
      }

      send(state.callback_pid, {:membrane_event, :completed, event})
    end
  end
end
