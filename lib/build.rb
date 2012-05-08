require "state_machine"
require "resque_jobs/deploy_build"
require "resque_jobs/run_tests"
require "lib/build_status"
require "timeout"

class Build < Sequel::Model
  one_to_many :build_statuses
  many_to_one :current_region, :class => Region
  add_association_dependencies :build_statuses => :destroy

  MONITORING_PERIOD_DURATION = 45 # seconds.

  REPO_DIRS = File.expand_path("~/immunity_repos/")

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
      transition :monitoring => :awaiting_confirmation, :if => :requires_manual_approval?
      transition :monitoring => :deploying, :if => proc { |build| !build.requires_manual_approval? }
    end

    event :manual_deploy_confirmed do
      transition :awaiting_confirmation => :awaiting_deploy
    end

    #
    # Operations which occur when state changes.
    #
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
      # TODO(philc): This mirroring source shouldn't be hard-coded to prod3.
      begin
        start_mirroring_traffic("prod3", current_region) unless application.is_test?
      rescue => error
        log_transition_failure("monitoring failed", error.detailed_to_s)
        self.fire_events(:monitoring_failed)
      end
    end

    after_transition :monitoring => any do
      # TODO(philc): This mirroring source shouldn't be hard-coded to prod3.
      begin
        stop_mirroring_traffic("prod3", current_region) unless application.is_test?
      rescue => error
        log_transition_failure("monitoring failed", error.detailed_to_s)
        self.fire_events(:monitoring_failed) unless state == "monitoring_failed"
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
    next_region = application.regions[application.regions.index(current_region) + 1]
    raise "Cannot pick a next region; this build's region is already the last." if next_region.nil?
    next_region
  end

  def requires_manual_approval?() self.current_region.requires_manual_approval? end

  # The first sandbox is deployed to continuously and doesn't run production monitoring using mirroed traffic.
  def requires_monitoring?() self.current_region.requires_monitoring? end

  def schedule_deploy
    puts "scheduling deploy to #{current_region.name} #{state}"
    Resque.enqueue(DeployBuild, repo, commit, current_region.name, id)
  end

  def schedule_test
    puts "Scheduling testing for #{current_region.name} #{state}"
    Resque.enqueue(RunTests, repo, current_region.name, id)
  end

  def start_mirroring_traffic(from_region, to_region)
    puts "Beginning to mirror traffic."
    run_command_with_timeout("bundle exec fez #{from_region.name} log_forwarding:start",
        "html5player/api_server", 4)
    run_command_with_timeout("bundle exec fez #{to_region.name} log_replay:start",
        "html5player/api_server", 4)
  end

  def stop_mirroring_traffic(from_region, to_region)
    puts "Ceasing to mirror traffic."
    run_command_with_timeout("bundle exec fez #{from_region.name} log_forwarding:stop",
        "html5player/api_server", 4)
    run_command_with_timeout("bundle exec fez #{to_region.name} log_replay:stop",
        "html5player/api_server", 4)
  end

  # TODO(philc): We should issue these commands in a nonblocking fashion.
  def run_command_with_timeout(command, project_path, timeout)
    project_path = File.join(REPO_DIRS, project_path)
    command = "BUNDLE_GEMFILE='' && cd #{project_path} && #{command}"
    puts "Running #{command}"
    Timeout.timeout(timeout) do
      pid, stdin, stdout, stderr = Open4::popen4(command)
      stdin.close
      ignored, status = Process::waitpid2 pid
      raise "The command #{command} failed: #{stderr.read.strip}" unless status.exitstatus == 0
      [stdout.read.strip, stderr.read.strip]
    end
  end

  # TODO(philc): Rip this out of here and put it into a separate object which records the summary data about
  # monitoring. It was put here for demo reasons.
  def monitoring_stats(region = self.current_region)
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
    BuildStatus.create(:build_id => self.id, :region => self.current_region,
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