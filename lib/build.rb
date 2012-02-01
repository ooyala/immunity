require "state_machine"
require "resque_jobs/deploy_build"
require "resque_jobs/run_tests"
require "lib/build_status"
require "timeout"

class Build < Sequel::Model
  one_to_many :build_statuses
  add_association_dependencies :build_statuses => :destroy

  @@regions = ["sandbox1", "sandbox2", "prod3"]
  REPO_DIRS = File.expand_path("~/immunity_repos/")
  def self.regions() @@regions end

  def initialize(values = {}, from_db = false)
    super
    self.current_region ||= @@regions.first
  end

  def readable_name() "Build #{id}" end

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
      schedule_deploy()
    end

    after_transition any => :testing do
      schedule_test()
    end

    after_transition any => :monitoring do
      enable_production_traffic_mirroring
      # TODO(philc): This mirroring source shouldn't be hard-coded to prod3.
      start_mirroring_traffic("prod3", current_region)
    end

    after_transition :monitoring => any do
      stop_mirroring_traffic("prod3", current_region)
    end

    after_transition any => :deploy_failed do
      notify_deploy_failed
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
    raise "This build has a region which is no longer defined" unless @@regions.include?(current_region)
    next_region = @@regions[@@regions.index(self.current_region) + 1]
    raise "Cannot pick a next region; this build's region is already the last." if next_region.nil?
    next_region
  end

  def requires_manual_deploy?() self.current_region == "sandbox2" end

  # The first sandbox is deployed to continuously and doesn't run production monitoring using mirroed traffic.
  def requires_monitoring?() self.current_region != "sandbox1" end

  # The Build which is next in line for a given region.
  def self.next_build_for_region(region_name)
    Build.order(:id.desc).first(:current_region => region_name, :state => "awaiting_deploy")
  end

  def enable_production_traffic_mirroring
    puts "enabling production traffic mirroring."
  end

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

  def notify_deploy_failed
    puts "deploy to #{current_region} failed."
    # TODO(philc): Raise the alarm.
  end

end