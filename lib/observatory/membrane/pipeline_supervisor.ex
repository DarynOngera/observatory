defmodule Observatory.Membrane.PipelineSupervisor do
  @moduledoc """
  Supervises Membrane pipelines for transformations.
  """

  use GenServer
  require Logger

  alias Observatory.ProcessSchema
  alias Observatory.Membrane.{TranscodePipeline, SimplePipeline}

  @type pipeline_ref :: reference()

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec start_pipeline(String.t(), String.t(), ProcessSchema.TransformConfig.t()) ::
          {:ok, pipeline_ref()} | {:error, term()}
  def start_pipeline(input_file, output_file, config) do
    GenServer.call(__MODULE__, {:start_pipeline, input_file, output_file, config}, 30_000)
  end

  @spec stop_pipeline(pipeline_ref()) :: :ok
  def stop_pipeline(ref) do
    GenServer.call(__MODULE__, {:stop_pipeline, ref})
  end

  @spec get_pipeline_state(pipeline_ref()) :: {:ok, ProcessSchema.t()} | {:error, :not_found}
  def get_pipeline_state(ref) do
    GenServer.call(__MODULE__, {:get_state, ref})
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    state = %{
      # ref => %{pid, process_schema}
      pipelines: %{}
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:start_pipeline, input_file, output_file, config}, _from, state) do
    ref = make_ref()

    # Validate files
    unless File.exists?(input_file) do
      {:reply, {:error, :input_file_not_found}, state}
    else
      # Create process schema
      process = ProcessSchema.new(input_file, output_file, config)
      process = ProcessSchema.mark_running(process)

      # Determine pipeline type
      pipeline_module = choose_pipeline_module(config)

      Logger.info("Starting #{inspect(pipeline_module)} for #{input_file} -> #{output_file}")

      # Start pipeline
      pipeline_opts = [
        input_file: input_file,
        output_file: output_file,
        config: config,
        callback_pid: self()
      ]

      case Membrane.Pipeline.start_link(pipeline_module, pipeline_opts) do
        # FIXED: Handle correct return tuple
        {:ok, supervisor_pid, pipeline_pid} ->
          # Monitor both
          Process.monitor(supervisor_pid)
          Process.monitor(pipeline_pid)

          pipeline_state = %{
            supervisor_pid: supervisor_pid,
            pipeline_pid: pipeline_pid,
            process: process,
            ref: ref
          }

          new_state = put_in(state.pipelines[ref], pipeline_state)
          {:reply, {:ok, ref}, new_state}

        {:error, reason} ->
          Logger.error("Failed to start pipeline: #{inspect(reason)}")
          {:reply, {:error, reason}, state}
      end
    end
  end

  @impl true
  def handle_call({:stop_pipeline, ref}, _from, state) do
    case Map.get(state.pipelines, ref) do
      %{pipeline_pid: pid} ->
        Membrane.Pipeline.terminate(pid)
        new_state = update_in(state.pipelines, &Map.delete(&1, ref))
        {:reply, :ok, new_state}

      nil ->
        {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_call({:get_state, ref}, _from, state) do
    case Map.get(state.pipelines, ref) do
      %{process: process} ->
        {:reply, {:ok, process}, state}

      nil ->
        {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_info({:membrane_event, :progress, event}, state) do
    new_state =
      update_all_pipelines(state, fn process ->
        ProcessSchema.add_event(process, event)
      end)

    {:noreply, new_state}
  end

  @impl true
  def handle_info({:membrane_event, :completed, event}, state) do
    pipeline_pid = event.data[:pipeline_pid]

    new_state =
      update_pipeline_by_pid(state, pipeline_pid, fn process ->
        stats = extract_stats_from_event(event)
        ProcessSchema.mark_completed(process, stats)
      end)

    {:noreply, new_state}
  end

  @impl true
  def handle_info({:membrane_event, :error, %{pipeline_pid: pid, error: error_msg}}, state) do
    new_state =
      update_pipeline_by_pid(state, pid, fn process ->
        ProcessSchema.mark_failed(process, error_msg)
      end)

    {:noreply, new_state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, reason}, state) do
    Logger.info("Pipeline process #{inspect(pid)} terminated: #{inspect(reason)}")

    # Find the pipeline and mark it as completed or failed
    new_state =
      update_in(state.pipelines, fn pipelines ->
        Enum.map(pipelines, fn {ref, pipeline_state} ->
          cond do
            pipeline_state.supervisor_pid == pid || pipeline_state.pipeline_pid == pid ->
              updated_process =
                case reason do
                  :normal ->
                    stats = %ProcessSchema.ProcessStats{
                      duration_sec: 0.0,
                      frames_processed: 0,
                      fps: 0.0,
                      bitrate_kbps: 0.0,
                      speed: 0.0,
                      size_bytes: 0,
                      quality_score: nil
                    }

                    ProcessSchema.mark_completed(pipeline_state.process, stats)

                  _ ->
                    ProcessSchema.mark_failed(pipeline_state.process, inspect(reason))
                end

              {ref, %{pipeline_state | process: updated_process}}

            true ->
              {ref, pipeline_state}
          end
        end)
        |> Map.new()
      end)

    {:noreply, new_state}
  end

  # Private functions

  defp choose_pipeline_module(config) do
    # Use SimplePipeline for copy operations (no transcoding)
    # Use TranscodePipeline when actual encoding is needed
    if needs_transcoding?(config) do
      TranscodePipeline
    else
      SimplePipeline
    end
  end

  defp needs_transcoding?(config) do
    config.codec != nil ||
      config.resolution != nil ||
      config.crf != nil ||
      config.gop_size != nil ||
      config.preset != nil
  end

  defp update_all_pipelines(state, fun) do
    new_pipelines =
      state.pipelines
      |> Enum.map(fn {ref, pipeline_state} ->
        {ref, %{pipeline_state | process: fun.(pipeline_state.process)}}
      end)
      |> Map.new()

    %{state | pipelines: new_pipelines}
  end

  defp update_pipeline_by_pid(state, pid, fun) do
    new_pipelines =
      state.pipelines
      |> Enum.map(fn {ref, pipeline_state} ->
        if pipeline_state.pipeline_pid == pid do
          {ref, %{pipeline_state | process: fun.(pipeline_state.process)}}
        else
          {ref, pipeline_state}
        end
      end)
      |> Map.new()

    %{state | pipelines: new_pipelines}
  end

  defp extract_stats_from_event(event) do
    data = event.data

    %ProcessSchema.ProcessStats{
      duration_sec: data[:duration_sec] || 0.0,
      frames_processed: data[:frames_processed] || 0,
      fps: data[:avg_fps] || 0.0,
      bitrate_kbps: 0.0,
      speed: 0.0,
      size_bytes: 0,
      quality_score: nil
    }
  end
end
