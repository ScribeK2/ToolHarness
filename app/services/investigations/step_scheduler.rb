module Investigations
  # Resolves and launches a track's dependent probes. Idempotent: only acts on a
  # dependent step that is still `pending` and whose dependency has reached a terminal
  # state. Designed to run inside InvestigationProgressJob's `with_lock` so concurrent
  # child-completion events can't double-enqueue. Enqueuing flips the step to
  # `processing`; an unresolvable dependency marks it `skipped` with a reason.
  # Single-use: the run snapshot is taken at construction, so build a fresh instance
  # per invocation rather than calling `call` twice on the same object.
  class StepScheduler
    def initialize(investigation)
      @inv  = investigation
      @runs = investigation.tool_runs.to_a.index_by(&:tool_key)
    end

    def call
      @inv.track_config.specs.each do |spec|
        next unless spec.depends_on

        step = @runs[spec.tool_key]
        next unless step&.status == "pending"

        dep = @runs[spec.depends_on]
        next unless dep && ToolRun::TERMINAL_STATUSES.include?(dep.status)

        resolve(spec, step, dep)
      end
    end

    private

    def resolve(spec, step, dep)
      target = resolve_target(spec.target, dep)

      if target.present?
        step.update!(status: "processing", input: { "domain" => target }, input_summary: target)
        ToolRunJob.perform_later(step.id)
      else
        step.update!(status: "skipped", skip_reason: skip_reason(spec, dep))
      end
    end

    def resolve_target(kind, dep)
      case kind.to_sym
      when :primary_mx_host then primary_mx_host(dep)
      end
    end

    def primary_mx_host(dep)
      return nil unless dep.success

      mx = Array((dep.result_data || {}).with_indifferent_access[:mx_records])
      return nil if mx.empty?

      # Lowest preference value = primary MX. Entries missing a priority sort last
      # rather than masquerading as priority 0 (the most-preferred slot).
      primary = mx.min_by { |m| m[:priority] ? m[:priority].to_i : Float::INFINITY }
      primary[:host].to_s.chomp(".").presence
    end

    def skip_reason(spec, dep)
      dep.success ? "No MX records — reputation check skipped" : "#{spec.depends_on} failed — no MX host to check"
    end
  end
end
