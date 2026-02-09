defmodule Observatory.Membrane.TranscodePipeline do
  @moduledoc """
  Membrane pipeline for transcoding operations with progress tracking.
  """

  use Membrane.Pipeline
  import Membrane.ChildrenSpec

  require Membrane.Logger

  alias Membrane.{File, MP4, H264, AAC, RawVideo}

  @impl true
  def handle_init(_ctx, opts) do
    input_file = Keyword.fetch!(opts, :input_file)
    output_file = Keyword.fetch!(opts, :output_file)
    config = Keyword.get(opts, :config, %{})

    spec = build_transcode_spec(input_file, output_file, config)

    state = %{
      input_file: input_file,
      output_file: output_file,
      config: config,
      start_time: System.monotonic_time(:millisecond),
      frame_count: 0,
      total_frames: nil
    }

    {[spec: spec], state}
  end

  @impl true
  def handle_child_notification({:end_of_stream, _pad}, _element, _ctx, state) do
    Membrane.Logger.info("Stream ended")
    send_completion_event(state)
    {[], state}
  end

  @impl true
  def handle_child_notification({:frame_encoded, _metadata}, _element, _ctx, state) do
    state = %{state | frame_count: state.frame_count + 1}
    send_progress_event(state)
    {[], state}
  end

  @impl true
  def handle_child_notification(notification, element, _ctx, state) do
    Membrane.Logger.debug("Notification from #{inspect(element)}: #{inspect(notification)}")
    {[], state}
  end

  # Build transcode pipeline specification
  defp build_transcode_spec(input_file, output_file, config) do
    video_config = Map.get(config, :video, %{})
    audio_config = Map.get(config, :audio, %{})

    children = [
      input_file: %File.Source{location: input_file},
      demuxer: MP4.Demuxer.ISOM,
      muxer: MP4.Muxer.ISOM,
      output_file: %File.Sink{location: output_file}
    ]

    links = [
      link(:input_file) |> to(:demuxer)
    ]

    # Add video pipeline if needed
    {children, links} = 
      if video_config[:enabled] != false do
        add_video_pipeline(children, links, video_config)
      else
        add_video_passthrough(children, links)
      end

    # Add audio pipeline if needed
    {children, links} = 
      if audio_config[:enabled] != false do
        add_audio_pipeline(children, links, audio_config)
      else
        {children, links}
      end

    # Connect muxer to output
    links = links ++ [link(:muxer) |> to(:output_file)]

    [
      children: children,
      links: links
    ]
  end

  # Add video encoding pipeline
  defp add_video_pipeline(children, links, config) do
    codec = Map.get(config, :codec, :h264)
    
    video_children = case codec do
      :h264 ->
        [
          video_parser: H264.Parser,
          video_decoder: H264.FFmpeg.Decoder,
          video_scaler: %RawVideo.FFmpeg.Scaler{
            width: Map.get(config, :width),
            height: Map.get(config, :height)
          },
          video_encoder: %H264.FFmpeg.Encoder{
            preset: Map.get(config, :preset, :medium),
            crf: Map.get(config, :crf, 23),
            max_b_frames: Map.get(config, :max_b_frames, 0)
          },
          video_parser_out: H264.Parser
        ]
      _ ->
        []
    end

    video_links = [
      link(:demuxer)
      |> via_out(Pad.ref(:output, {:video, 0}))
      |> to(:video_parser)
      |> to(:video_decoder)
      |> to(:video_scaler)
      |> to(:video_encoder)
      |> to(:video_parser_out)
      |> via_in(Pad.ref(:input, :video))
      |> to(:muxer)
    ]

    {children ++ video_children, links ++ video_links}
  end

  # Add video passthrough (no transcoding)
  defp add_video_passthrough(children, links) do
    video_links = [
      link(:demuxer)
      |> via_out(Pad.ref(:output, {:video, 0}))
      |> via_in(Pad.ref(:input, :video))
      |> to(:muxer)
    ]

    {children, links ++ video_links}
  end

  # Add audio encoding pipeline
  defp add_audio_pipeline(children, links, config) do
    codec = Map.get(config, :codec, :aac)
    
    audio_children = case codec do
      :aac ->
        [
          audio_decoder: AAC.Decoder,
          audio_encoder: %AAC.Encoder{
            bitrate: Map.get(config, :bitrate, 128_000)
          }
        ]
      _ ->
        []
    end

    audio_links = [
      link(:demuxer)
      |> via_out(Pad.ref(:output, {:audio, 0}))
      |> via_in(Pad.ref(:input, :audio))
      |> to(:muxer)
    ]

    {children ++ audio_children, links ++ audio_links}
  end

  # Event helpers
  defp send_progress_event(state) do
    elapsed_ms = System.monotonic_time(:millisecond) - state.start_time
    
    event = %{
      type: :progress,
      frames_encoded: state.frame_count,
      elapsed_ms: elapsed_ms,
      fps: calculate_fps(state.frame_count, elapsed_ms)
    }

    send(self(), {:transcode_event, event})
  end

  defp send_completion_event(state) do
    elapsed_ms = System.monotonic_time(:millisecond) - state.start_time
    
    event = %{
      type: :complete,
      total_frames: state.frame_count,
      elapsed_ms: elapsed_ms,
      output_file: state.output_file
    }

    send(self(), {:transcode_event, event})
  end

  defp calculate_fps(frame_count, elapsed_ms) when elapsed_ms > 0 do
    frame_count / (elapsed_ms / 1000)
  end

  defp calculate_fps(_, _), do: 0.0
end
