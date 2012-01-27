# A Resque job to run "git pull" on a given repo and add an entry for the latest commit.

require "pathological"
require "script/script_environment"
require "resque_jobs/jobs_helper"
require "resque"
require "open4"
require "fileutils"

class DeployBuild
  include JobsHelper
  @queue = :deply_builds

  REPO_DIRS = File.expand_path("~/immunity_repos/")
  
  REGION_TO_SERVER = {
    "sandbox1" => "rui@127.0.0.1",
    "sandbox2" => "root@ec2-107-22-34-118.compute-1.amazonaws.com"
  }

  def self.perform(repo, commit, current_region, build_id)
    setup_logger("deply_builds.log")
    begin
      self.deploy_commit(repo, commit, current_region)
      #self.run_command("curl http://localhost:3103/deploy_succeed/#{build_id} >/dev/null")
    rescue
      #self.run_command("curl http://localhost:3103/deploy_failed/#{build_id} >/dev/null")
    end
  end

  def self.deploy_commit(repo_name, commit, region)
    @logger.info "deploy the commit #{repo_name}, #{commit}"
    project_repo = File.join(REPO_DIRS, repo_name)
    results = self.run_command("cd #{project_repo} && ./run_deploy.sh #{REGION_TO_SERVER[region]}")
    puts results
  end


  def self.run_command(command)
    # use open4 instead of open3 here, because oepn3 does not like fezzik, when running fez deploy using
    # open3, it pop error message which suggesting to use open4 instead.
    pid, stdin, stdout, stderr = Open4::popen4 command
    stdin.close
    ignored, status = Process::waitpid2 pid
    raise "The command #{command} failed: #{stderr.read.strip}" unless status.exitstatus == 0
    stdout.read.strip
  end
end

if $0 == __FILE__
  DeployBuild.perform('html5player', '7d1cca5b679959f0820d21d59e0c4371d025175d', 'sandbox1', 1)
end
