require "state_machine"
require "resque_jobs/deploy_build"
require "resque_jobs/run_tests"
require "lib/build_status"
require "timeout"

class Build < Sequel::Model
  one_to_many :build_statuses
  add_association_dependencies :build_statuses => :destroy

  REPO_DIRS = File.expand_path("~/immunity_repos/")

  def initialize(values = {}, from_db = false)
    super
    self.current_region ||= Region.region_names.first
  end

  def readable_name() "Build #{id} (#{short_commit})" end

  # An abbreviated commit SHA instead of the usual long SHA.
  def short_commit() (commit || "")[0..6] end

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
      transition :awaiting_confirmation => :awaiting_deploy
    end

    #
    # Operations which occur when state changes.
    #
    after_transition any => :awaiting_deploy do |transition|
      self.current_region = next_region
    end

    after_transition any => :deploying do
      schedule_deploy() unless is_test_build?
    end

    after_transition any => :testing do
      schedule_test() unless is_test_build?
    end

    after_transition any => :monitoring do
      # TODO(philc): This mirroring source shouldn't be hard-coded to prod3.
      begin
        start_mirroring_traffic("prod3", current_region) unless is_test_build?
      rescue => error
        log_transition_failure("monitoring failed", error.detailed_to_s)
        self.fire_events(:monitoring_failed)
      end
    end

    after_transition :monitoring => any do
      # TODO(philc): This mirroring source shouldn't be hard-coded to prod3.
      begin
        stop_mirroring_traffic("prod3", current_region) unless is_test_build?
      rescue => error
        log_transition_failure("monitoring failed", error.detailed_to_s)
        self.fire_events(:monitoring_failed) unless state == "monitoring_failed"
      end
    end

    after_transition any => :deploy_failed do
      notify_deploy_failed unless is_test_build?
    end

    after_transition any => any do
      self.save
    end
  end

  # False if there's another Build already being deployed to the current region.
  def region_is_available_for_deploy?
    nonblocking_states = %W(deploy_failed awaiting_confirmation testing_failed monitoring_failed awaiting_deploy)
    blocked = Build.filter(:repo => repo, :current_region => current_region).
        filter("state NOT IN ?", nonblocking_states).count > 0
    !blocked
  end

  # The next region in the deploy chain after the current region.
  def next_region
    unless Region.region_names.include?(current_region)
      raise "This build has a region which is no longer defined"
    end
    next_region = Region.region_names[Region.region_names.index(self.current_region) + 1]
    next_region = "integration_test_#{next_region}" if current_region.include?("integration_test_")
    raise "Cannot pick a next region; this build's region is already the last." if next_region.nil?
    next_region
  end

  def requires_manual_deploy?() self.current_region.include?("sandbox2") end

  # The first sandbox is deployed to continuously and doesn't run production monitoring using mirroed traffic.
  def requires_monitoring?() !self.current_region.include?("sandbox1") end

  def schedule_deploy
    puts "scheduling deploy to #{current_region} #{state}"
    Resque.enqueue(DeployBuild, repo, commit, current_region, id)
  end

  def schedule_test
    puts "Scheduling testing for #{current_region} #{state}"
    Resque.enqueue(RunTests, repo, current_region, id)
  end

  def start_mirroring_traffic(from_region, to_region)
    puts "Beginning to mirror traffic."
    run_command_with_timeout("bundle exec fez #{from_region} log_forwarding:start",
        "html5player/api_server", 4)
    run_command_with_timeout("bundle exec fez #{to_region} log_replay:start",
        "html5player/api_server", 4)
  end

  def stop_mirroring_traffic(from_region, to_region)
    puts "Ceasing to mirror traffic."
    run_command_with_timeout("bundle exec fez #{from_region} log_forwarding:stop",
        "html5player/api_server", 4)
    run_command_with_timeout("bundle exec fez #{to_region} log_replay:stop",
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
    self.current_region = "sandbox1"
    self.state = "awaiting_deploy"
    self.save
    self.build_statuses_dataset.destroy
    self.fire_events(:begin_deploy)
  end

  def is_test_build?() self.is_test_build end

end