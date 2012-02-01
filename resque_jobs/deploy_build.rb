# A Resque job to run "git pull" on a given repo and add an entry for the latest commit.

require "pathological"
require "script/script_environment"
require "resque_jobs/jobs_helper"
require "resque"
require "open4"
require "fileutils"
require 'rest_client'

class DeployBuild
  include JobsHelper
  @queue = :deply_builds

  REPO_DIRS = File.expand_path("~/immunity_repos/")

  def self.perform(repo, commit, current_region, build_id)
    setup_logger("deply_builds.log")
    begin
      stdout_message, stderr_message = self.deploy_commit(repo, commit, current_region)
      RestClient.post 'http://localhost:3102/deploy_succeed', :build_id => build_id, :stdout => stdout_message,
          :stderr => stderr_message, :region => current_region,
      #self.run_command("curl /#{build_id} >/dev/null")
    rescue Exception => e
      RestClient.post 'http://localhost:3102/deploy_failed', :build_id => build_id, :message => 'Deploy Error',
          :stdout => '', :stderr => "#{e.message}\n#{e.backtrace}", :region => current_region,
    end
  end

  def self.deploy_commit(repo_name, commit, region)
    @logger.info "deploying the commit #{REPO_DIRS}: #{repo_name}, #{commit}, #{region}"
    project_repo = File.join(REPO_DIRS, repo_name)
    results = self.run_command("cd #{project_repo} && ./run_deploy.sh #{region}")
    results
  end
end

if $0 == __FILE__
  DeployBuild.perform('html5player', 'a583b85dcb2d47932f9bf4a9a221fe4a8baccef8', 'sandbox1', 18)
end
