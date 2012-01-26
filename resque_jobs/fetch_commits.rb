# A Resque job to run "git pull" on a given repo and add an entry for the latest commit.

require "bundler/setup"
require "pathological"
require "script/script_environment"
require "resque_jobs/jobs_helper"
require "resque"
require "open3"

class FetchCommits
  include JobsHelper
  @queue = :fetch_commits

  REPO_DIRS = File.expand_path("~/immunity_repos/")

  def self.perform
    setup_logger("fetch_commits.log")
    fetch_commits()
    # Reconnect to the database if our connection has timed out.
    # Build.select(1).first rescue nil
  end

  def self.fetch_commits()
    @logger.info "Fetching the newest commits."
    return # TODO(philc): Remove this return statement

    repo_name = "html5player"

    @logger.info "Fetching new commits from #{repo_name}."

    project_repo = File.join(REPO_DIRS, repo_name)
    run_command("cd #{project_repo} && git fetch")
    latest_commit = run_command(`cd #{project_repo} && git rev-list --max-count=1 head`).strip
  end

  def run_command(command)
    stdout, stderr, status = Open3.capture3(command)
    Open3.popen3(command) { |stdin, stdout, stderr| stdout_stream = stdout }
    raise "The command #{command} failed: #{stderr}" unless status == 0
    stdout
  end
end

if $0 == __FILE__
  FetchCommits.perform
end
