class ToolRun < ApplicationRecord
  STATUSES = %w[pending processing completed failed].freeze

  enum :status, STATUSES.zip(STATUSES).to_h

  belongs_to :investigation, optional: true

  validates :tool_key, :tool_name, :category, presence: true

  scope :recent,         -> { order(created_at: :desc) }
  scope :successful,     -> { where(success: true) }
  scope :failed_runs,    -> { where(success: false) }
  scope :for_category,   ->(cat) { where(category: cat.to_s) }
  scope :for_tool,       ->(key) { where(tool_key: key.to_s) }
  scope :search_input,   ->(q) { q.present? ? where("input_summary LIKE ?", "%#{sanitize_sql_like(q)}%") : all }

  def self.create_pending!(tool_class:, params:, investigation: nil, step_order: nil)
    create!(
      tool_key: tool_class.name.demodulize.underscore,
      tool_name: tool_class.tool_name,
      category: tool_class.category.to_s,
      input_type: tool_class.input_type.to_s,
      input: normalize_params(params),
      input_summary: build_input_summary(params),
      status: "pending",
      investigation_id: investigation&.id,
      step_order: step_order
    )
  end

  def self.record(tool_class:, params:, result:, started_at: nil, completed_at: nil)
    run = create_pending!(tool_class: tool_class, params: params)
    run.apply_result!(result, started_at: started_at, completed_at: completed_at)
    run
  end

  def tool_class
    ToolHarness::Registry.find_tool(tool_key)
  end

  # Raw value of the tool's primary input field — used to hand a target off
  # to a sibling tool. Falls back to input_summary if the tool is gone.
  def primary_input
    klass = tool_class
    return input_summary unless klass

    key = klass.form_fields.keys.first.to_s
    input[key].presence || input_summary
  end

  def apply_result!(result, started_at: nil, completed_at: nil)
    completed = completed_at || Time.current
    started   = started_at || self.started_at || (completed - (result.execution_time || 0).seconds)

    update!(
      status: result.success? ? "completed" : "failed",
      success: result.success?,
      result_data: result.data || {},
      issues: result.issues || [],
      recommendations: result.recommendations || [],
      summary: result.summary,
      error: result.error,
      execution_time: result.execution_time,
      cached: result.cached || false,
      checked_at: self.class.parse_iso(result.checked_at),
      started_at: started,
      completed_at: completed
    )
  end

  def self.build_input_summary(params)
    h = params.to_h.with_indifferent_access

    # Bulk: "N domains via tool_key"
    if h[:domains].present?
      count = h[:domains].to_s.split(/[\s,;]+/).reject(&:empty?).size
      via   = h[:tool_key].present? ? " via #{h[:tool_key]}" : ""
      return "#{count} domain#{'s' unless count == 1}#{via}"
    end

    if h[:sql].present?
      one_line = h[:sql].to_s.gsub(/\s+/, " ").strip
      return one_line.length > 80 ? "#{one_line[0, 79]}…" : one_line
    end

    primary = h[:domain] || h[:email] || h[:ip] || h[:ticket_id] || h[:server] || h[:host]
    return nil if primary.blank?

    port = h[:port].presence
    port ? "#{primary}:#{port}" : primary.to_s
  end

  def self.normalize_params(params)
    params.respond_to?(:to_unsafe_h) ? params.to_unsafe_h : params.to_h
  end

  def self.parse_iso(value)
    return nil if value.blank?
    return value if value.is_a?(Time) || value.is_a?(DateTime)
    Time.iso8601(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end

  RETENTION_CAP = 5000

  def self.purge_older_than!(duration)
    cutoff = duration.ago
    where("created_at < ?", cutoff).delete_all
  end

  def self.enforce_retention_cap!(cap: RETENTION_CAP)
    over = count - cap
    return 0 if over <= 0
    ids = order(:created_at).limit(over).pluck(:id)
    where(id: ids).delete_all
    over
  end

  after_create_commit :enforce_cap_async
  after_update_commit :notify_investigation

  private

  def notify_investigation
    return unless investigation_id
    return unless saved_change_to_status? && %w[completed failed].include?(status)
    InvestigationProgressJob.perform_later(investigation_id)
  end

  def enforce_cap_async
    # Quick inline check; if over cap, sweep oldest. Cheap because we only run on insert.
    self.class.enforce_retention_cap! if self.class.count > RETENTION_CAP
  end
end
