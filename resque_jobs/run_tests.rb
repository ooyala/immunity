# A Resque job to run "git pull" on a given repo and add an entry for the latest commit.

require "pathological"
require "script/script_environment"
require "resque_jobs/jobs_helper"
require "resque"
require "fileutils"
require "rest_client"

class RunTests
  include JobsHelper
  @queue = :run_tests

  REPO_DIRS = File.expand_path("~/immunity_repos/")

  HOST = "http://localhost:3102"

  def self.perform(repo, region_name, build_id)
    setup_logger("run_tests.log")
    begin
      region = Build.first(:id => build_id).application.region_with_name(region_name)
      stdout, stderr = self.start_tests(repo, region)
      cleaned_output = stdout.gsub(/\D0 failure/, "").gsub(/\D0 error/, "")
      test_failure = /(\d+) failure/.match(cleaned_output)
      test_error = /(\d+) errors/.match(cleaned_output)
      if test_failure || test_error
        puts "Tests failed: #{(test_failure || test_error).inspect} #{stdout}"
        RestClient.put "#{HOST}/builds/#{build_id}/testing_status",
            { :status => "failed", :log => stdout, :region => region_name }.to_json
      else
        puts "Test succeeded. #{stdout}"
        RestClient.put "#{HOST}/builds/#{build_id}/testing_status",
            { :status => "success", :log => stdout, :region => region_name }.to_json
      end
    rescue Exception => error
      message = "Unable to run the tests: #{error.detailed_to_s}"
      puts message
      RestClient.put "#{HOST}/builds/#{build_id}/testing_status",
          { :status => "failed", :log => message, :region => region_name }.to_json
    end
  end

  def self.start_tests(repo_name, region)
    @logger.info "Running tests for #{repo_name} #{region.name}"
    project_repo = File.join(REPO_DIRS, repo_name)
    result = self.run_command("cd #{project_repo} && ./run_tests.sh #{region.name} 2>&1")
  end
end

if $0 == __FILE__
  RunTests.perform("html5player", "sandbox1", 1)
end
