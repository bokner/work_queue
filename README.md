WorkQueue
=========

A simple implementation of the _hungry consumer_ work scheduling model.

Given a queue of work to be processed, we create a a pool of workers.
Each worker requests the next item to process from the queue. When it
finishes processing, it reports the result back and then requests the
next item of work.

The itent is that we do not need a central control point which
preassigns work—that is done dynamically by the workers.

This has a couple of advantages. First, it locally maximizes CPU
utilization, as workers are always busy as long as there is work in
the queue.

Second, it offers a degree of resilience, both against CPU hogging
work items and against worker failure.

Simple Example
==============

    results = WorkQueue.start_link(
      fn val -> { :ok, val*2 },   # worker function
      [ 1, 2, 3 ]                 # work items to process
    )

    assert length(results) == 3
    for {input, output} <- results, do: assert(output == input * 2)


This code will allocate a number of workers (the default is 2/3rds of
the available processing units in the node). Each worker then runs
the given function for as long as there are items to process. The
results are collected (in the order the workers return them) and
returned.


The API
=======

   results = WorkQueue.start_link(work_processor, item_source, options \\ [])


* `work_processor` is a function tht transforms an item from the work
  queue. It receives a value, and returns either `{:ok, result}` or
  `{:error, reason}`

* `item_source` is the fata representing the source of the items to be
  processed. In the simplest case, this is just an enumerable.
  Successive items are taken from it and fed to the workers.

  In other situations, you may need to perform additional processing
  in order to generate the items. In particular, the item source may
  be unbounded. In this case, you need to provide a `get_next_item`
  function (using the options—see below). This function receives the
  `item_source` as its initial state.

* `options` is an optional keyword list:

  * `worker_count: ` _count_

     If count is an integer, start that number of workers. If it is a
     float, it becomes a factor by which we multiply the number of
     processing units on the node (so specifying `0.5` will start
     workers for one-half the number of available processing units).
     You can also pass the symbols `:cpu_bound` and `:io_bound`. The
     former creates a worker for each processing unit, the latter
     creates 10 workers per processing unit.

  * `report_each_result_to: ` _func_

     Invoke `func` as each result becomes available. The function
     receives a tuple containing the original work item and the result
     of running the calculation on that item. Its return value is
     ignored.

         ```` 
         test "notifications of results" do
           WorkQueue.start_link(
             &double/2,
             [ 1, 2, 3 ],
             report_each_result_to:
               fn {input, output} -> assert(output == input*2) end
           )
         end
         ````
         
  * `report_progress_to:` _func_, `report_progress_interval:` _ms_

     Invoke `func` to report progress. It is passed

     * `{:starting}` when work is about to start
     * `{:progress,` _count_`}` every `ms` milliseconds, indicating
       the total number of items processed so far
     * `{:finished,` _results_`}` reported when processing finishes

     Progress reporting is disabled when `report_progress_interval` is
     `false` (the default).
     
  
