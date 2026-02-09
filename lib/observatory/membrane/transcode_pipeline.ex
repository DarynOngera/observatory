defmodule Observatory.Membrane.TranscodePipeline do
  @moduledoc """
  Membrane pipeline for media transcoding with video transformation support.
  """
  use Membrane.Pipeline

  require Membrane.Logger

  alias Membrane.{File, MP4, H264}
  alias Membrane.FFmpeg.SWScale

  @impl true
  def handle_init(_ctx, opts) do
    input_file = Keyword.fetch!(opts, :input_file)
    output_file = Keyword.fetch!(opts, :output_file)
    config = Keyword.get(opts, :config, %{})

    # Build initial spec with input, demuxer, muxer, and output
    spec = [
      child(:input_file, %File.Source{location: input_file})
      |> child(:demuxer, MP4.Demuxer.ISOM),
      child(:muxer, MP4.Muxer.ISOM)
      |> child(:output_file, %File.Sink{location: output_file})
    ]

    # Build video config from flat config structure
    video_config =
      %{
        codec: Map.get(config, :codec),
        width: Map.get(config, :resolution) |> elem(0),
        height: Map.get(config, :resolution) |> elem(1),
        preset: Map.get(config, :preset),
        crf: Map.get(config, :crf),
        gop_size: Map.get(config, :gop_size)
      }
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()

    state = %{
      input_file: input_file,
      output_file: output_file,
      config: config,
      video_config: video_config,
      stream_count: 0,
      completed_streams: 0,
      start_time: System.monotonic_time(:millisecond),
      frame_count: 0
    }

    {[spec: spec], state}
  end

  @impl true
  def handle_child_notification(
        {:new_stream, track_id, %Membrane.H264{} = _stream_format},
        :demuxer,
        _ctx,
        state
      ) do
    Membrane.Logger.info("New H264 video stream detected: track_id=#{track_id}")

    video_config = state.video_config

    spec =
      if video_config[:codec] do
        # Transcode path
        build_video_transcode_spec(track_id, video_config)
      else
        # Passthrough path
        build_video_passthrough_spec(track_id)
      end

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

    # Try to passthrough unknown streams
    spec =
      get_child(:demuxer)
      |> via_out(Pad.ref(:output, track_id))
      |> via_in(Pad.ref(:input, track_id), options: [track_id: track_id])
      |> get_child(:muxer)

    new_state = %{state | stream_count: state.stream_count + 1}
    {[spec: spec], new_state}
  end

  @impl true
  def handle_element_end_of_stream(:output_file, _pad, _ctx, state) do
    Membrane.Logger.info("Output file completed")
    {[terminate: :normal], state}
  end

  @impl true
  def handle_element_end_of_stream(element, _pad, _ctx, state) do
    completed = state.completed_streams + 1

    Membrane.Logger.info(
      "Element completed: #{inspect(element)} (#{completed}/#{state.stream_count})"
    )

    {[], %{state | completed_streams: completed}}
  end

  # Private functions

  defp build_video_transcode_spec(track_id, config) do
    has_resolution = Map.get(config, :width) != nil && Map.get(config, :height) != nil

    encoder_opts = %H264.FFmpeg.Encoder{
      preset: Map.get(config, :preset, :medium),
      crf: Map.get(config, :crf, 23)
    }

    # Build the processing chain
    chain =
      get_child(:demuxer)
      |> via_out(Pad.ref(:output, track_id))
      |> child({:video_parser, track_id}, H264.Parser)
      |> child({:video_decoder, track_id}, H264.FFmpeg.Decoder)

    # Add scaler only if resolution is specified
    chain =
      if has_resolution do
        scaler_opts = %{
          output_width: Map.get(config, :width),
          output_height: Map.get(config, :height)
        }

        chain
        |> child({:video_scaler, track_id}, struct!(SWScale.Scaler, scaler_opts))
        |> child({:video_encoder, track_id}, encoder_opts)
      else
        chain
        |> child({:video_encoder, track_id}, encoder_opts)
      end

    # Add output parser and connect to muxer
    chain =
      chain
      |> child({:video_parser_out, track_id}, H264.Parser)

    # Return the full spec
    [
      chain,
      get_child({:video_parser_out, track_id})
      |> via_in(Pad.ref(:input, track_id), options: [track_id: track_id])
      |> get_child(:muxer)
    ]
  end

  defp build_video_passthrough_spec(track_id) do
    # Direct passthrough from demuxer to muxer
    get_child(:demuxer)
    |> via_out(Pad.ref(:output, track_id))
    |> via_in(Pad.ref(:input, track_id), options: [track_id: track_id])
    |> get_child(:muxer)
  end
end
