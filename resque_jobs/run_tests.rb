# A Resque job to run "git pull" on a given repo and add an entry for the latest commit.

require "pathological"
require "script/script_environment"
require "resque_jobs/jobs_helper"
require "resque"
require "open4"
require "fileutils"
require 'rest_client'

class RunTests
  include JobsHelper
  @queue = :run_tests

  REPO_DIRS = File.expand_path("~/immunity_repos/")
  
  # todo, hard code the mapping here for now, need to change to use fez to start the task instead.
  REGION_TO_SERVER = {
    "sandbox1" => "#{ENV['USER']}@127.0.0.1",
    "sandbox2" => "#{ENV['USER']}@127.0.0.1",
    "prod3" => "#{ENV['USER']}@127.0.0.1"
  }

  def self.perform(repo, current_region, build_id)
    setup_logger("run_tests.log")
    begin
      stdout_message, stderr_message = self.start_tests(repo, current_region)
      cleaned_output = stdout_message.gsub(/\D0 failure/, '').gsub(/\D0 error/, '')
      test_fail = /(\d+) failure/.match(cleaned_output)
      test_error = /(\d+) errors/.match(cleaned_output)
      if test_fail || test_error
        puts "test failed here #{test_fail.inspect} #{stderr_message}"
        RestClient.post 'http://localhost:3102/test_failed', :build_id => build_id, :region => current_region,
          :stdout => stdout_message, :stderr => stderr_message, :message => "test fail"
      else
        puts "Test succeed.#{stdout_message}"
        RestClient.post 'http://localhost:3102/test_succeed', :build_id => build_id, :region => current_region,
          :stdout => stdout_message, :stderr => stderr_message, :message => "test succeed -- #{Time.now}\n"
      end
    rescue Exception => e
      puts "Test with exception #{e.backtrace}"
      RestClient.post 'http://localhost:3102/test_failed', :build_id => build_id, :region => current_region,
          :stdout => "", :stderr => "#{e.message}\n#{e.backtrace}", :message => "test error"
    end
  end

  def self.start_tests(repo_name, region)
    # TODO (Rui) For POC, run the remote ssh command for now, for real world work, we should make a JENKINS
    # call to start the test and wait for the JENKIN callback for test results.
    # should be good for demo purpose for now.
    @logger.info "run test the  #{REPO_DIRS}: #{repo_name}, #{region}"
    project_repo = File.join(REPO_DIRS, repo_name)
    remote_command = "source ~/.profile; /opt/ooyala/#{region}/#{repo_name}/run_tests.sh"
    # TODO(philc): We should do this with fezzik, so we don't have to build up the path ourself here.
    results = self.run_command("ssh #{REGION_TO_SERVER[region]} '#{remote_command}'")
    results
  end


  def self.run_command(command)
    # use open4 instead of open3 here, because oepn3 does not like fezzik, when running fez deploy using
    # open3, it pop error message which suggesting to use open4 instead.
    pid, stdin, stdout, stderr = Open4::popen4 command
    stdin.close
    ignored, status = Process::waitpid2 pid
    raise "The command #{command} failed: #{stderr.read.strip}" unless status.exitstatus == 0
    [stdout.read.strip, stderr.read.strip]
  end
end

if $0 == __FILE__
  RunTests.perform('html5player', 'sandbox1', 1)
end
