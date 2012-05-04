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

  def self.perform(repo_name, commit, region_name, build_id)
    setup_logger("deply_builds.log")
    begin
      stdout = self.deploy_commit(repo, commit, region_name, build_id)
      # TODO(philc): This will return success even if the deploy failed. Check the exit value of fez instead.
      RestClient.put "#{HOST}/builds/#{build_id}/deploy_status",
          { :status => "success", :log => stdout, :region => region_name }.to_json
    rescue Exception => error
      message = "Failure running the deploy: #{error.detailed_to_s}"
      RestClient.put "#{HOST}/builds/#{build_id}/deploy_status",
          { :status => "failed", :log => message, :region => region_name }.to_json
    end
  end

  def self.deploy_commit(repo_name, commit, region_name, build_id)
    region = Build.first(:id => build_id).application.region_with_name(region_name)
    @logger.info "deploying the commit #{REPO_DIRS}: #{repo_name}, #{commit}, #{region.name}"
    project_repo = File.join(REPO_DIRS, repo_name)
    # TODO(philc): Extract out this command into configuration.
    stdout, stderr = self.run_command("cd #{project_repo} && ./run_deploy.sh #{region.name} 2>&1")
    stdout
  end
end

if $0 == __FILE__
  DeployBuild.perform("html5player", "a583b85dcb2d47932f9bf4a9a221fe4a8baccef8", "sandbox1", 18)
end
