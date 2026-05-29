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
  after_create_commit :enforce_cap_async

  private

  def enforce_cap_async
    return unless self.class.count > RETENTION_CAP
    over = self.class.count - RETENTION_CAP
    ids  = self.class.order(:created_at).limit(over).pluck(:id)
    self.class.where(id: ids).delete_all
  end
end
