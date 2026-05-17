class ToolRun < ApplicationRecord
  belongs_to :user

  STATUSES = %w[pending processing completed failed].freeze

  enum :status, STATUSES.zip(STATUSES).to_h

  validates :tool_key, :tool_name, :category, presence: true

  scope :recent,         -> { order(created_at: :desc) }
  scope :successful,     -> { where(success: true) }
  scope :failed_runs,    -> { where(success: false) }
  scope :for_category,   ->(cat) { where(category: cat.to_s) }
  scope :for_tool,       ->(key) { where(tool_key: key.to_s) }
  scope :search_input,   ->(q) { q.present? ? where("input_summary LIKE ?", "%#{sanitize_sql_like(q)}%") : all }

  def self.create_pending!(user:, tool_class:, params:)
    create!(
      user: user,
      tool_key: tool_class.name.demodulize.underscore,
      tool_name: tool_class.tool_name,
      category: tool_class.category.to_s,
      input_type: tool_class.input_type.to_s,
      input: normalize_params(params),
      input_summary: build_input_summary(params),
      status: "pending"
    )
  end

  def self.record(user:, tool_class:, params:, result:, started_at: nil, completed_at: nil)
    run = create_pending!(user: user, tool_class: tool_class, params: params)
    run.apply_result!(result, started_at: started_at, completed_at: completed_at)
    run
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
end
