class Investigation < ApplicationRecord
  STATUSES = %w[pending running completed].freeze
  VERDICTS = %w[healthy issues critical].freeze

  has_many :tool_runs, -> { order(:step_order) }, dependent: :nullify, inverse_of: :investigation

  validates :domain, :track, presence: true
  validates :status, inclusion: { in: STATUSES }

  scope :recent, -> { order(created_at: :desc) }

  def running?  = status == "running"
  def completed? = status == "completed"

  def all_steps_terminal?
    runs = tool_runs.to_a
    runs.any? && runs.all? { |r| %w[completed failed].include?(r.status) }
  end

  def track_config = Investigations::Track.find(track)

  RETENTION_CAP = 5000

  def self.enforce_retention_cap!(cap: RETENTION_CAP)
    over = count - cap
    return 0 if over <= 0
    ids = order(:created_at).limit(over).pluck(:id)
    ToolRun.where(investigation_id: ids).update_all(investigation_id: nil)
    where(id: ids).delete_all
    over
  end

  after_create_commit :enforce_cap_async

  private

  def enforce_cap_async
    self.class.enforce_retention_cap! if self.class.count > RETENTION_CAP
  end
end
