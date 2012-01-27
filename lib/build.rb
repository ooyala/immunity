require "state_machine"
class Build < Sequel::Model
  @@regions = ["sandbox1", "sandbox2", "prod_region1", "prod_region2"]

  def initialize(values = {}, from_db = false)
    super
    self.current_region ||= @@regions.first
  end

  state_machine :state, :initial => :awaiting_deploy do

    #
    # Events and the state changes they cause.
    #
    event :begin_deploy do
      transition :awaiting_deploy => :deploying, :if => :region_is_available_for_deploy?
    end

    event :deploy_failed do
      transition :deploying => :deploy_failed
    end

    event :deploy_succeeded do
      transition :deploying => :ready_to_test
    end

    event :begin_testing do
      transition :ready_to_test => :testing
    end

    event :testing_failed do
      transition :testing => :testing_failed
    end

    event :testing_succeeded do
      transition :testing => :monitoring, :if => :requires_monitoring?
      transition :testing => :awaiting_deploy
    end

    event :monitoring_failed do
      transition :monitoring => :monitoring_failed
    end

    event :monitoring_succeeded do
      transition :monitoring => :awaiting_confirmation, :if => :requires_manual_deploy?
      # TODO(philc): This is the wrong state transition. Fix.
      transition :monitoring => :deploying
    end

    event :manual_deploy_confirmed do
      transition :awaiting_confirmation => :deploying
    end

    #
    # Operations which occur when state changes.
    #
    after_transition any => :awaiting_deploy do |transition|
      self.current_region = next_region
    end

    after_transition any => :deploying do
      schedule_deploy()
    end

    after_transition any => :monitoring do
      enable_production_traffic_mirroring
    end

    after_transition any => :deploy_failed do
      notify_deploy_failed
    end
  end

  # False if there's another Build already being deployed to the current region.
  def region_is_available_for_deploy?
    nonblocking_states = %W(deploy_failed awaiting_confirmation testing_failed monitoring_failed awaiting_deploy)
    blocked = Build.filter(:repo => repo, :current_region => current_region).
        filter("state NOT IN ?", nonblocking_states).count > 0
    !blocked
  end

  def next_region
    raise "This build has a region which is no longer defined" unless @@regions.include?(current_region)
    next_region = @@regions[@@regions.index(self.current_region) + 1]
    raise "Cannot pick a next region; this build's region is already the last." if next_region.nil?
    next_region
  end

  def requires_manual_deploy?() self.current_region == "sandbox2" end

  # The first sandbox is deployed to continuously and doesn't run production monitoring using mirroed traffic.
  def requires_monitoring?() self.current_region != "sandbox1" end

  def enable_production_traffic_mirroring
    puts "enabling production traffic mirroring."
  end

  def schedule_deploy
    puts "scheduling deploy to #{current_region}."
  end

  def notify_deploy_failed
    puts "deploy to #{current_region} failed."
  end

end