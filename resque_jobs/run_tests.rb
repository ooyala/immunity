# A Resque job which invokes the integration tests for a deployed build.
# This job needs to be reimplemented to use Application.test_command.

require "pathological"
require "script/script_environment"
require "resque_jobs/jobs_helper"
require "resque"
require "fileutils"
require "rest_client"

class RunTests
  include JobsHelper
  @queue = :run_tests

  HOST = "http://localhost:3102"

  def self.perform(region_name, build_id)
    setup_logger("run_tests.log")
    begin
      application = Build.first(:id => build_id).application
      region = application.region_with_name(region_name) # Should be region id for consistency
      stdout, stderr = self.start_tests(region)
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

  # TODO use path logic in deploy_build
  def self.start_tests(region)
    application = region.application
    @logger.info "Running tests for #{application.name} #{region.name}"
    test_command = application.substitute_variables(application.test_command, :region => region.name)
    result = self.run_command("cd #{application.repo_path} && #{test_command} 2>&1")
  end
end

if $0 == __FILE__
  RunTests.perform("html5player", "sandbox1", 1)
end
