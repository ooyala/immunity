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

  # The arguments hash is used by our integration tests to test each main logic path.
  # - repos: the list of repo names to git fetch.
  def self.perform(arguments = {})
    logger ||= setup_logger("fetch_commits.log")
    logger.info("beginning to perform fetch_commits")

    # Reconnect to the database if our connection has timed out.
    Build.select(1).first rescue nil

    begin
      # TODO(philc): This repo name shouldn't be hardcoded here.
      repos = arguments["repos"] || ["html5player"]
      fetch_commits(repos)
    rescue => exception
      logger.info("Failed to complete job: #{exception}")
      raise exception
    end
  end

  def self.fetch_commits(applications)
    applications.each do |app_name|
      logger.info "Fetching new commits from #{app_name}."

      application = Application.first(:name => app_name)
      unless application
        logger.error "Application #{app_name} was not found in the DB."
        next
      end

      repo = File.join(REPOS_ROOT, app_name)
      unless File.exists?(repo)
        logger.error "Cannot pull from #{repo} -- it doesn't exist on disk."
        next
      end

      # We perform a "git reset --hard head" in case we've accidentally modified the build during a deploy,
      # e.g. by running `bundle install` which can modify Gemfile.lock.
      run_command("cd #{repo} && git reset --hard origin/master && git pull")
      run_command("cd #{repo} && git pull")
      latest_commit = run_command("cd #{repo} && git rev-list --max-count=1 HEAD").strip

      if Build.first(:commit => latest_commit, :repo => repo).nil?
        logger.info "#{repo} has new commits. The latest is now #{latest_commit}."
        build = Build.create(:commit => latest_commit, :repo => repo,
            :current_region_id => application.regions.first.id)
        build.fire_events(:begin_deploy)
      end
    end
  end

  # TODO(philc): Get rid of this in favor of open4.
  def self.run_command(command)
    stdout, stderr, status = Open3.capture3(command)
    Open3.popen3(command) { |stdin, stdout, stderr| stdout_stream = stdout }
    raise %Q(The command "#{command}" failed: #{stderr}) unless status == 0
    stdout
  end
end

if $0 == __FILE__
  FetchCommits.perform
end
