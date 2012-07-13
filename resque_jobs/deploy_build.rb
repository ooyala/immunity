# A Resque job which deploys a build to a given region.

require "pathological"
require "script/script_environment"
require "resque_jobs/jobs_helper"
require "resque"
require "fileutils"
require "rest_client"

class DeployBuild
  include JobsHelper
  @queue = :deply_builds

  IMMUNITY_HOST = "http://localhost:3102"

  # - arguments: { build_id, region_id (optional) }
  def self.perform(arguments = {})
    setup_logger("deply_builds.log")

    # Reconnect to the database if our connection has timed out.
    Build.select(1).first rescue nil

    begin
      build = Build[arguments["build_id"]]
      region = arguments["region_id"] ? Region[arguments["region_id"]] : build.current_region
      stdout = deploy_commit(build, region)
      RestClient.put "#{IMMUNITY_HOST}/builds/#{build.id}/deploy_status",
          { :status => "success", :log => stdout, :region => region.name }.to_json
    rescue Exception => error
      message = "Failure running the deploy: #{error.detailed_to_s}"
      logger.warn message
      RestClient.put "#{IMMUNITY_HOST}/builds/#{build.id}/deploy_status",
          { :status => "failed", :log => message, :region => region.name }.to_json
    end
  end

  def self.deploy_commit(build, region)
    application = region.application
    @logger.info "deploying the commit #{application.name} #{build.commit} to #{region.name}."
    deploy_command = application.substitute_variables(application.deploy_command, :region => region.name)
    stdout, stderr = run_command("unset BUNDLE_GEMFILE; cd #{application.repo_path} && #{deploy_command} 2>&1")
    stdout
  end
end

if $0 == __FILE__
  DeployBuild.perform({ "build_id" => Build.first.id })
end
