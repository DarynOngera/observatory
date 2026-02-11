defmodule Observatory.Membrane.TranscodePipeline do
  @moduledoc """
  Membrane pipeline for media transcoding with video transformation support.
  """
  use Membrane.Pipeline

  require Membrane.Logger

  alias Membrane.{File, MP4, H264}
  alias Membrane.FFmpeg.SWScale
  alias Observatory.ProcessSchema

  @impl true
  def handle_init(_ctx, opts) do
    input_file = Keyword.fetch!(opts, :input_file)
    output_file = Keyword.fetch!(opts, :output_file)
    config = Keyword.fetch!(opts, :config)
    callback_pid = Keyword.get(opts, :callback_pid)

    Membrane.Logger.info("Transcode pipeline starting: #{input_file} -> #{output_file}")
    Membrane.Logger.info("Config: #{inspect(config)}")

    # initial spec with input, demuxer, muxer, and output

    spec = [
      child(:input_file, %File.Source{location: input_file})
      |> child(:demuxer, MP4.Demuxer.ISOM),
      child(:muxer, MP4.Muxer.ISOM)
      |> child(:output_file, %File.Sink{location: output_file})
    ]

    state = %{
      input_file: input_file,
      output_file: output_file,
      config: config,
      callback_pid: callback_pid,
      started_at: DateTime.utc_now(),
      stream_count: 0,
      completed_streams: 0,
      frames_processed: 0,
      muxer_finished: false,
      output_finished: false,
      completion_sent: false
    }

    {[spec: spec], state}
  end

  @impl true
  def handle_child_notification(
        {:new_stream, track_id, %Membrane.H264{} = _format},
        :demuxer,
        _ctx,
        state
      ) do
    Membrane.Logger.info("H264 video stream detected: track_id: #{track_id}")

    spec = build_video_pipeline(track_id, state.config)
    new_state = %{state | stream_count: state.stream_count + 1}

    {[spec: spec], new_state}
  end

  @impl true
  def handle_child_notification(
        {:new_stream, track_id, %Membrane.AAC{} = _stream_format},
        :demuxer,
        _ctx,
        state
      ) do
    Membrane.Logger.info("New AAC audio stream detected: track_id=#{track_id}")

    # For now, passthrough audio
    spec =
      get_child(:demuxer)
      |> via_out(Pad.ref(:output, track_id))
      |> via_in(Pad.ref(:input, track_id), options: [track_id: track_id])
      |> get_child(:muxer)

    new_state = %{state | stream_count: state.stream_count + 1}
    {[spec: spec], new_state}
  end

  @impl true
  def handle_child_notification({:new_stream, track_id, stream_format}, :demuxer, _ctx, state) do
    Membrane.Logger.warning(
      "Unknown stream format: track_id=#{track_id}, format=#{inspect(stream_format)}"
    )

    spec =
      get_child(:demuxer)
      |> via_out(Pad.ref(:output, track_id))
      |> via_in(Pad.ref(:input, track_id), options: [track_id: track_id])
      |> get_child(:muxer)

    new_state = %{state | stream_count: state.stream_count + 1}
    {[spec: spec], new_state}
  end

  @impl true
  def handle_element_end_of_stream(:output_file, pad, _ctx, state) do
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

  # Private functions

  defp build_video_pipeline(track_id, config) do
    needs_encode = config.codec != nil || config.resolution != nil || config.crf != nil

    if needs_encode do
      build_transcode_chain(track_id, config)
    else
      build_passthrough_chain(track_id)
    end
  end

  def build_transcode_chain(track_id, config) do
    Membrane.Logger.info("Building transcode chain for track #{track_id}")

    encoder_opts = %H264.FFmpeg.Encoder{
      preset: config.preset || :medium,
      crf: config.crf || 23
    }

    chain =
      get_child(:demuxer)
      |> via_out(Pad.ref(:output, track_id))
      |> child({:parser_in, track_id}, H264.Parser)
      |> child({:decoder, track_id}, H264.FFmpeg.Decoder)

    chain =
      if config.resolution do
        {width, height} = config.resolution
        Membrane.Logger.info("Adding scaler: #{width}x#{height}")

        chain
        |> child({:scaler, track_id}, %SWScale.Scaler{
          output_width: width,
          output_height: height
        })
      else
        chain
      end

    chain
    |> child({:encoder, track_id}, encoder_opts)
    |> child({:parser_out, track_id}, H264.Parser)
    |> via_in(Pad.ref(:input, track_id), options: [track_id: track_id])
    |> get_child(:muxer)
  end

  defp build_passthrough_chain(track_id) do
    Membrane.Logger.info("Building passthrough chain for track #{track_id}")

    get_child(:demuxer)
    |> via_out(Pad.ref(:output, track_id))
    |> via_in(Pad.ref(:input, track_id), options: [track_id: track_id])
    |> get_child(:muxer)
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
        message: "Transcoding completed",
        data: %{
          frames_processed: state.frames_processed,
          duration_sec: duration,
          pipeline_pid: self()
        }
      }

      send(state.callback_pid, {:membrane_event, :completed, event})
    end
  end
end
