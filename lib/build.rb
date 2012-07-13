require "state_machine"
require "resque_jobs/deploy_build"
require "resque_jobs/run_tests"
require "lib/build_status"
require "timeout"
require "rest_client"

# NOTE(philc): Be careful when developing; some types of changes to this state machine do not completely
# unload and reload with Sinatra reloader.
class Build < Sequel::Model
  one_to_many :build_statuses
  many_to_one :current_region, :class => Region
  add_association_dependencies :build_statuses => :destroy

  MONITORING_PERIOD_DURATION = 45 # seconds.

  def readable_name() "Build #{id} (#{short_commit})" end

  # An abbreviated commit SHA instead of the usual long SHA.
  def short_commit() (commit || "")[0..6] end

  def application() self.current_region ? self.current_region.application : nil end

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
      transition :testing => :awaiting_deploy, :if => proc { |build| !build.requires_monitoring? }
    end

    event :monitoring_failed do
      transition :monitoring => :monitoring_failed
    end

    event :monitoring_succeeded do
      transition :monitoring => :monitoring_failed, :unless => :halt_mirroring
      transition :monitoring => :awaiting_confirmation, :if => :requires_manual_approval?
      transition :monitoring => :awaiting_deploy, :if => proc { |build| !build.requires_manual_approval? }
    end

    event :manual_deploy_confirmed do
      transition :awaiting_confirmation => :awaiting_deploy
    end

    #
    # Operations which occur when state changes.
    #

    after_transition :monitoring => :monitoring_failed do
      halt_mirroring
    end

    after_transition any => :awaiting_deploy do |transition|
      self.current_region = next_region
    end

    after_transition any => :deploying do
      schedule_deploy() unless application.is_test?
    end

    after_transition any => :testing do
      schedule_test() unless application.is_test?
    end

    after_transition any => :monitoring do
      unless application.is_test?
        start_mirroring_traffic(application.next_region(current_region), current_region)
      end
    end

    after_transition any => :deploy_failed do
      notify_deploy_failed unless application.is_test?
    end

    after_transition any => any do
      self.save
    end
  end

  # False if there's another Build already being deployed to the current region.
  def region_is_available_for_deploy?
    nonblocking_states = %W(deploy_failed awaiting_confirmation testing_failed monitoring_failed awaiting_deploy)
    blocked = current_region.builds_dataset.filter("state NOT IN ?", nonblocking_states).count > 0
    !blocked
  end

  # The next region in the deploy chain after the current region.
  def next_region
    next_region = application.next_region(current_region)
    raise "Cannot pick a next region; this build's region is already the last." if next_region.nil?
    next_region
  end

  def requires_manual_approval?() self.current_region.requires_manual_approval? end

  # The first sandbox is deployed to continuously and doesn't run production monitoring using mirroed traffic.
  def requires_monitoring?
    has_next_region = !application.next_region(current_region).nil?
    has_next_region && current_region.requires_monitoring?
  end

  def schedule_deploy
    puts "Scheduling deploy to #{current_region.name} #{state}"
    Resque.enqueue(DeployBuild, repo, commit, current_region.name, id)
  end

  def schedule_test
    puts "Scheduling testing for #{current_region.name} #{state}"
    Resque.enqueue(RunTests, repo, current_region.name, id)
  end

  def start_mirroring_traffic(from_region, to_region)
    puts "Beginning to mirror traffic from #{from_region.name} to region #{to_region.name}"
    redis_queue = "log_forwarding:#{application.name}:#{from_region.name}"
    begin
      RestClient.post("#{from_region.host}:#{LOG_FORWARDER_PORT}/status",
          :enabled => true,
          # TODO(philc): this log_file_name should be part of the app's configuration.
          :log_file_name => "/opt/ooyala/player_api/logs/log.txt",
          :redis_host => LOG_FORWARDING_REDIS_HOST,
          :redis_queue => redis_queue)
    rescue Errno::ECONNREFUSED, RestClient::Exception => error
      log_monitoring_failure(error)
      fire_events(:monitoring_failed)
    end

    # TODO(philc): Start log replay.

  end

  # Returns true if successful.
  def stop_mirroring_traffic(from_region, to_region)
    puts "Stopping to mirror traffic from #{from_region.name}."
    error = nil
    begin
      RestClient.post("#{from_region.host}:#{LOG_FORWARDER_PORT}/status", :enabled => false)
    rescue Errno::ECONNREFUSED, RestClient::Exception => error
      log_monitoring_failure(error)
    end

    return error.nil?

    # TODO(philc): Stop the log replay.

  end

  def halt_mirroring()
    return true if application.is_test?
    stop_mirroring_traffic(current_region, next_region)
  end

  def log_monitoring_failure(raised_error)
    details = raised_error.respond_to?(:response) ? raised_error.response.body : ""
    details += raised_error.backtrace.join("\n")
    log_transition_failure(raised_error.message, details)
  end

  # TODO(philc): Rip this out of here and put it into a separate object which records the summary data about
  # monitoring. It was put here for demo reasons.
  def monitoring_stats(region = current_region)
    redis = Redis.new :host => "localhost"
    today = "2012-02-14" # TODO(philc): 
    request_count = redis.get("#{region.name}_request_count").to_i
    errors = redis.get("html5player:error_count:#{today}").to_i
    error_rate = (request_count == 0) ? 0 : (errors / request_count.to_f * 100)
    latency = (request_count == 0) ? 0 : redis.get("#{region.name}_latency").to_i / request_count
    {
      :request_count => request_count,
      :average_latency => latency,
      :error_count => errors,
      :error_rate => error_rate
    }
  end

  # Creates a BuildStatus for this build, with the given details.
  def log_transition_failure(message, further_details)
    BuildStatus.create(:build_id => self.id, :region_id => current_region.id,
        :message => message, :stdout => further_details)
  end

  def notify_deploy_failed
    puts "deploy to #{current_region} failed."
    # TODO(philc): Raise the alarm.
  end

  # A debugging method we use via ./script/console to make the system treat this build as a fresh new commit.
  def treat_as_new_commit!
    self.current_region = self.application.regions.first
    self.state = "awaiting_deploy"
    self.build_statuses_dataset.destroy
    self.save
    self.fire_events(:begin_deploy)
  end
end