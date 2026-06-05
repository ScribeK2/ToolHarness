class Batch < ApplicationRecord
  STATUSES = %w[running completed].freeze

  has_many :tool_runs, -> { order(:step_order) }, dependent: :nullify, inverse_of: :batch

  validates :tool_key, presence: true
  validates :status, inclusion: { in: STATUSES }

  scope :recent, -> { order(created_at: :desc) }

  def all_children_terminal?
    r = tool_runs.to_a
    r.any? && r.all? { |x| ToolRun::TERMINAL_STATUSES.include?(x.status) }
  end

  def done_count     = tool_runs.to_a.count { |r| ToolRun::TERMINAL_STATUSES.include?(r.status) }
  def success_count  = tool_runs.to_a.count { |r| r.status == "completed" && r.success }
  def failure_count  = tool_runs.to_a.count { |r| r.status == "failed" || (r.status == "completed" && !r.success) }
  def total_critical = tool_runs.to_a.sum { |r| Array(r.issues).count { |i| (i["severity"] || i[:severity]).to_s == "critical" } }
  def tool_class     = ToolHarness::Registry.find_tool(tool_key)

  RETENTION_CAP = 2000
  after_create_commit :enforce_cap_async

  def self.enforce_retention_cap!(cap: RETENTION_CAP)
    over = count - cap
    return 0 if over <= 0
    ids = order(:created_at).limit(over).pluck(:id)
    ToolRun.where(batch_id: ids).update_all(batch_id: nil)
    where(id: ids).delete_all
    over
  end

  private

  def enforce_cap_async
    self.class.enforce_retention_cap! if self.class.count > RETENTION_CAP
  end
end
