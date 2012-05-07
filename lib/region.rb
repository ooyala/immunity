require "simple_memoize"

# This represents a deployable region (e.g. "sandbox1" or "sandbox2") and all builds associated with that region.
class Region < Sequel::Model
  many_to_one :application
  one_to_many :builds, :key => :current_region_id
  one_to_many :build_statuses
  add_association_dependencies :builds => :destroy, :build_statuses => :destroy

  # The build in this region which is currently in progress.
  def in_progress_build
    active_states = ["deploying", "testing", "monitoring", "awaiting_confirmation"]
    builds_dataset.reverse_order(:id).filter(:state => active_states).first
  end

  # The next build in line that's awaiting deploy. TODO(philc): Rename this.
  def next_build
    builds_dataset.order(:id.desc).first(:state => "awaiting_deploy")
  end

  def build_history
    build_statuses_dataset.order(:id.desc).limit(10).all
  end

  def requires_manual_deploy?() requires_manual_deploy end

  memoize :next_build, :in_progress_build, :build_history
end