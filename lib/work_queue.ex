defmodule WorkQueue do

  use PipeWhileOk

  require Logger

  alias WorkQueue.Options

  @doc File.read!("README.md")

  def process(worker_fn, item_source, extra_opts \\ []) do
    pipe_while_ok do
      package_parameters(worker_fn, item_source, extra_opts)
      |> Options.analyze
      |> start_workers
      |> schedule_work
    end
  end

  defp package_parameters(worker_fn, item_source, extra_opts) do
    { :ok,
      %{
          worker_fn:        worker_fn,
          item_source:      item_source,
          opts:             extra_opts,
          results:          []
       }
    }
  end

  defp start_workers(params) do
    WorkQueue.WorkerSupervisor.start_link(params)
  end

  defp schedule_work(params) do
    params.opts.report_progress_to.({:started, nil})

    results = if params.opts.report_progress_interval do
                loop_with_ticker(params, [], params.opts.worker_count)
              else
                loop(params, [], params.opts.worker_count)
              end

    params.opts.report_progress_to.({:finished, results})
    results
  end

  defp loop_with_ticker(params, running, max) do
    {:ok, ticker} = :timer.send_interval(params.opts.report_progress_interval,
                                         self, :tick)
    count = loop(params, running, max)
    :timer.cancel(ticker)
    count
  end

  defp loop(params, running, max) when length(running) < max do
    case get_next_item(params) do
      {:done, params, _} when running == [] ->
        Process.unlink(params.supervisor_pid)
        Process.exit(params.supervisor_pid, :shutdown)
        params.results

      {:done, params, _} ->
        wait_for_answers(params, running, max)

      {:ok, params, item} ->
        {:ok, worker} = WorkQueue.Worker.process(params, self(), item)
        loop(params, [worker|running], max)
    end
  end

  defp loop(params, running, max) do
    wait_for_answers(params, running, max)
  end

  defp wait_for_answers(params, running, max) do
    receive do
      :tick ->
        params.opts.report_progress_to.({:progress, length(params.results)})
        loop(params, running, max)
      { :processed, worker, { :ok, result } } ->
        if worker in running do
          params = update_in(params.results, &[result|&1])
          loop(params, List.delete(running, worker), max)
        else
          loop(params, running, max)
        end
    end
  end

  defp get_next_item(params) do
    {status, item, new_state}  = params.opts.get_next_item.(params.item_source)
    {status, Dict.put(params, :item_source, new_state), item}
  end
end
