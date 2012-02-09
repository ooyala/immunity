# A Resque job to run "git pull" on a given repo and add an entry for the latest commit.

require "pathological"
require "script/script_environment"
require "resque_jobs/jobs_helper"
require "resque"
require "fileutils"
require "rest_client"

class DeployBuild
  include JobsHelper
  @queue = :deply_builds

  REPO_DIRS = File.expand_path("~/immunity_repos/")

  HOST = "http://localhost:3102"

  def self.perform(repo, commit, current_region, build_id)
    setup_logger("deply_builds.log")
    begin
      stdout = self.deploy_commit(repo, commit, current_region)
      # TODO(philc): This will return success even if the deploy failed. Check the exit value of fez instead.
      RestClient.put "#{HOST}/builds/#{build_id}/deploy_status",
          { :status => "success", :log => stdout }.to_json
    rescue Exception => e
      message = "Failure running the deploy: #{e.message}\n#{e.backtrace}"
      RestClient.put "#{HOST}/builds/#{build_id}/deploy_status",
          { :status => "failed", :log => message }.to_json
    end
  end

  def self.deploy_commit(repo_name, commit, region)
    @logger.info "deploying the commit #{REPO_DIRS}: #{repo_name}, #{commit}, #{region}"
    project_repo = File.join(REPO_DIRS, repo_name)
    stdout, stderr = self.run_command("cd #{project_repo} && ./run_deploy.sh #{region} 2>&1")
    stdout
  end
end

if $0 == __FILE__
  DeployBuild.perform('html5player', 'a583b85dcb2d47932f9bf4a9a221fe4a8baccef8', 'sandbox1', 18)
end
