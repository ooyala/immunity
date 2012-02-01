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
    @logger.info "run test the  #{REPO_DIRS}: #{repo_name}, #{region}"
    project_repo = File.join(REPO_DIRS, repo_name)
    result = self.run_command("cd #{project_repo} && ./run_tests.sh #{region}")
  end
end

if $0 == __FILE__
  RunTests.perform('html5player', 'sandbox1', 1)
end
