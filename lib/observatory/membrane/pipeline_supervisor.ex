defmodule Observatory.Membrane.PipelineSupervisor do
  @moduledoc """
  Supervises Membrane pipelines for transformations.

  Manages pipeline lifecycle and event collection.
  """

  use GenServer

  require Logger

  alias Observatory.ProcessSchema
  alias Observatory.Membrane.{TransformPipeline, TranscodePipeline}

  @type pipeline_ref :: reference()

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Starts a transformation pipeline.

  Returns a reference that can be used to track progress.
  """
  @spec start_pipeline(String.t(), String.t(), ProcessSchema.TransformConfig.t()) ::
          {:ok, pipeline_ref()} | {:error, term()}
  def start_pipeline(input_file, output_file, config) do
    GenServer.call(__MODULE__, {:start_pipeline, input_file, output_file, config})
  end

  @doc """
  Stops a running pipeline.
  """
  @spec stop_pipeline(pipeline_ref()) :: :ok
  def stop_pipeline(ref) do
    GenServer.call(__MODULE__, {:stop_pipeline, ref})
  end

  @doc """
  Gets the current state of a pipeline.
  """
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

    # Create process schema
    process = ProcessSchema.new(input_file, output_file, config)
    process = ProcessSchema.mark_running(process)

    # Determine pipeline type based on config
    pipeline_module =
      if needs_transcoding?(config) do
        TranscodePipeline
      else
        TransformPipeline
      end

    # Start pipeline
    pipeline_opts = [
      input_file: input_file,
      output_file: output_file,
      config: config,
      callback_pid: self()
    ]

    case Membrane.Pipeline.start_link(pipeline_module, pipeline_opts) do
      {:ok, pid, _supervisor_pid} ->
        # Monitor the pipeline
        Process.monitor(pid)

        # Store in state
        pipeline_state = %{
          pid: pid,
          process: process,
          ref: ref
        }

        new_state = put_in(state.pipelines[ref], pipeline_state)

        {:reply, {:ok, ref}, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:stop_pipeline, ref}, _from, state) do
    case Map.get(state.pipelines, ref) do
      %{pid: pid} ->
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
    # Update all pipelines with this event
    # (In production, you'd track which pipeline sent this)
    new_state =
      update_all_pipelines(state, fn process ->
        ProcessSchema.add_event(process, event)
      end)

    {:noreply, new_state}
  end

  @impl true
  def handle_info({:membrane_event, :completed, event}, state) do
    # Mark pipeline as completed
    new_state =
      update_all_pipelines(state, fn process ->
        stats = extract_stats_from_event(event)
        ProcessSchema.mark_completed(process, stats)
      end)

    {:noreply, new_state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, reason}, state) do
    # Pipeline crashed or terminated
    Logger.info("Pipeline #{inspect(pid)} terminated: #{inspect(reason)}")

    # Find and remove the pipeline
    new_state =
      update_in(state.pipelines, fn pipelines ->
        Enum.reject(pipelines, fn {_ref, %{pid: p}} -> p == pid end)
        |> Map.new()
      end)

    {:noreply, new_state}
  end

  # Private functions

  defp needs_transcoding?(config) do
    config.codec != nil ||
      config.resolution != nil ||
      config.crf != nil ||
      config.gop_size != nil
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

  defp extract_stats_from_event(event) do
    data = event.data

    %ProcessSchema.ProcessStats{
      duration_sec: data[:duration_sec] || 0.0,
      frames_processed: data[:frames_processed] || 0,
      fps: data[:avg_fps] || 0.0,
      # Will be calculated from output file
      bitrate_kbps: 0.0,
      speed: 0.0,
      size_bytes: 0,
      quality_score: nil
    }
  end
end
