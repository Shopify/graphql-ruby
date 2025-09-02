# frozen_string_literal: true
module GraphQL
  class Dataloader
    class AsyncDataloader < Dataloader
      def yield(source = Fiber[:__graphql_current_dataloader_source])
        trace = Fiber[:__graphql_current_multiplex]&.current_trace
        trace&.dataloader_fiber_yield(source)
        if (condition = Fiber[:graphql_dataloader_next_tick])
          condition.wait
        else
          Fiber.yield
        end
        trace&.dataloader_fiber_resume(source)
        nil
      end

      def run(trace_query_lazy: nil)
        # TODO unify the initialization lazies_at_depth
        @lazies_at_depth ||= Hash.new { |h, k| h[k] = [] }
        trace = Fiber[:__graphql_current_multiplex]&.current_trace
        jobs_fiber_limit, total_fiber_limit = calculate_fiber_limit
        job_fibers = []
        next_job_fibers = []
        source_tasks = []
        next_source_tasks = []
        first_pass = true
        sources_condition = Async::Condition.new
        manager = spawn_fiber do
          trace&.begin_dataloader(self)
          while first_pass || !job_fibers.empty?
            first_pass = false
            fiber_vars = get_fiber_variables

            run_pending_steps(job_fibers, next_job_fibers, source_tasks, jobs_fiber_limit, trace)

            Sync do |root_task|
              set_fiber_variables(fiber_vars)
              while !source_tasks.empty? || @source_cache.each_value.any? { |group_sources| group_sources.each_value.any?(&:pending?) }
                while (task = (source_tasks.shift || (((job_fibers.size + next_job_fibers.size + source_tasks.size + next_source_tasks.size) < total_fiber_limit) && spawn_source_task(root_task, sources_condition, trace))))
                  if task.alive?
                    root_task.yield # give the source task a chance to run
                    next_source_tasks << task
                  end
                end
                sources_condition.signal
                source_tasks.concat(next_source_tasks)
                next_source_tasks.clear
              end
            end

            if !@lazies_at_depth.empty?
              with_trace_query_lazy(trace_query_lazy) do
                run_next_pending_lazies(job_fibers, trace)
                run_pending_steps(job_fibers, next_job_fibers, source_tasks, jobs_fiber_limit, trace)
              end
            elsif !@steps_to_rerun_after_lazy.empty?
              @pending_jobs.concat(@steps_to_rerun_after_lazy)
              f = spawn_job_fiber(trace)
              job_fibers << f
              @steps_to_rerun_after_lazy.clear
            end
          end
          trace&.end_dataloader(self)
        end

        manager.resume
        if manager.alive?
          raise "Invariant: Manager didn't terminate successfully: #{manager}"
        end

      rescue UncaughtThrowError => e
        throw e.tag, e.value
      end

      private

      def run_pending_steps(job_fibers, next_job_fibers, source_tasks, jobs_fiber_limit, trace)
        while (f = (job_fibers.shift || (((job_fibers.size + next_job_fibers.size + source_tasks.size) < jobs_fiber_limit) && spawn_job_fiber(trace))))
          if f.alive?
            finished = run_fiber(f)
            if !finished
              next_job_fibers << f
            end
          end
        end
        job_fibers.concat(next_job_fibers)
        next_job_fibers.clear
      end

      def spawn_source_task(parent_task, condition, trace)
        pending_sources = nil
        @source_cache.each_value do |source_by_batch_params|
          source_by_batch_params.each_value do |source|
            if source.pending?
              pending_sources ||= []
              pending_sources << source
            end
          end
        end

        if pending_sources
          fiber_vars = get_fiber_variables
          parent_task.async do
            trace&.dataloader_spawn_source_fiber(pending_sources)
            set_fiber_variables(fiber_vars)
            Fiber[:graphql_dataloader_next_tick] = condition
            pending_sources.each do |s|
              trace&.begin_dataloader_source(s)
              s.run_pending_keys
              trace&.end_dataloader_source(s)
            end
            cleanup_fiber
            trace&.dataloader_fiber_exit
          end
        end
      end
    end
  end
end
