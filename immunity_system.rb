#!/usr/bin/env ruby
require "bundler/setup"
require "pathological"
require "script/script_environment"
require "redis"
require "redis/list"
require "redis/sorted_set"
require "redis/objects"
require "sinatra"
require "sass"
require "bourbon"
require "lib/sinatra_api_helpers"
require "config/environment"

class ImmunitySystem < Sinatra::Base
  include SinatraApiHelpers

  # Arbitrary number; might consider increasing since it aggregates across all deploy ins
  MAX_NUM_SUCCESSES = 10
  MAX_NUM_RECENT_ERRORS = 30
  # 14 days expiration period
  REDIS_LOG_EXPIRATION = 60*60*24*14
  
  set :public_folder, "public"

  set :show_exceptions, false

  configure :development do
    error(400) do
      # Printing the response body for 400's is useful for debugging in development.
      puts response.body
    end
  end

  #
  # Views
  #
  get "/" do
    regions = Region.region_names.map { |name| Region.new(name) }
    # TODO(philc): We will pass in a list of regions to the frontend, not just a single build.
    latest_build = Build.order(:id).last
    erb :"index.html", :locals => { :regions => regions }
  end

  get "/styles.css" do
    scss :styles
  end

  get "/build_status/:id" do
    build_status = BuildStatus.first(:id => params[:id])
    show_error(404) unless build_status
    erb :"build_status.html", :locals => { :build_status => build_status }
  end

  # Manually confirms that a build is OK and begins deploying it to prod3.
  # - build_id
  post "/manual_deploy_confirmed" do
    build = Build.first(:id => params[:build_id])
    build.fire_events(:manual_deploy_confirmed)
    build.fire_events(:begin_deploy)
    nil
  end

  #
  # APIs
  #

  # Create a new Build. Used by our integration tests.
  # - commit
  # - current_region
  # - repo
  post "/builds" do
    enforce_required_json_keys(:current_region, :commit, :repo)
    build = Build.create(:current_region => json_body[:current_region],
        :is_test_build => json_body[:is_test_build], :commit => json_body[:commit],
        :repo => json_body[:repo])
    build.fire_events(:begin_deploy)
    build.to_json
  end

  before "/builds/:id/?*" do
    return if params[:id] == "test_builds"
    @build = enforce_valid_build(params[:id])
  end

  get "/builds/:id" do
    @build.to_json
  end

  # Private, used only by our integration tests. This needs to come before the delete "/builds/:id" route.
  delete "/builds/test_builds" do
    Build.filter(:is_test_build => true).destroy
    nil
  end

  delete "/builds/:id" do
    @build.destroy
    nil
  end

  # Mark a deploy as finished.
  # - status: "success" or "failed".
  # - log: detailed log information.
  # - region
  put "/builds/:id/deploy_status" do
    enforce_required_json_keys(:status, :log, :region)
    build_status = create_build_status("deploy", json_body)
    log_current_state(params[:id], nil, json_body[:log], json_body[:region], json_body[:status], 'building')

    if json_body[:status] == "success"
      @build.fire_events(:deploy_succeeded)
      @build.fire_events(:begin_testing)
    else
      @build.fire_events(:deploy_failed)
    end
    build_status.to_json
  end

  # Mark testing as finiished.
  # - status: "success" or "failed".
  # - log: detailed log information.
  # - region
  put "/builds/:id/testing_status" do
    enforce_required_json_keys(:status, :log, :region)
    build_status = create_build_status("testing", json_body)

    stderr_from_test = json_body[:stderr] ? json_body[:stderr] : nil
    log_current_state(params[:id], stderr_from_test, json_body[:log], json_body[:region], json_body[:status], 'testing')

    if json_body[:status] == "success"
      @build.fire_events(:testing_succeeded)
      @build.fire_events(:begin_deploy)
    else
      @build.fire_events(:testing_failed)
    end
    build_status.to_json
  end

  # Mark monitoring as finiished.
  # - status: "success" or "failed".
  # - log: detailed log information.
  # - region
  put "/builds/:id/monitoring_status" do
    enforce_required_json_keys(:status, :log, :region)
    build_status = create_build_status("monitoring", json_body)

    log_current_state(params[:id], nil, json_body[:log], json_body[:region], json_body[:status], 'monitoring')
    if json_body[:status] == "success"
      @build.fire_events(:monitoring_succeeded)
    else
      @build.fire_events(:monitoring_failed)
    end
    build_status.to_json
  end

  # Display helpers used by our views.
  helpers do
    # Takes in a state name like "deploy_failed" and translates to "Deploy failed".
    def format_name(state)
      state.gsub("_", " ").capitalize
    end

    # Produces a time in the form of "Fri 8:23pm 30s"
    def format_time(time)
      return "" if time.nil?
      time.strftime("%a %l:%M%P %Ss")
    end
  end

  # Creates a BuildStatus entry which records the state of the build.
  # - stage: one of "deploy", "testing", "monitoring"
  def create_build_status(stage, json_body)
    status = json_body[:status]
    show_error(400, "Invalid status.") unless ["success", "failed"].include?(status)
    message = (status == "success") ? "#{stage} succeeded" : "#{stage} failed."
    BuildStatus.create(:build_id => @build.id, :message => message, :stdout => json_body[:log],
        :region => json_body[:region])
  end

  def log_current_state(build_id, stderr_text=nil, message, region, status_type, operating_mode)
    # Save to redis so that we can pull from it when we setup our dashboard
    # status_type = [deploy_failed, deploy_success, test_failed, test_success, monitor_failed, monitor_success]
    day = Time.now.gmtime
    # TODO(snir): Need to figure out a centralized redis cache for the machines that will be deployed to
    redis = Redis.new(:host => REDIS_HOST, :port => REDIS_PORT)
    if (status_type.index("failed"))
      # TODO (snir): Probably want to add more fields to the info hash. For now, this is all we have...
      info_hash = {
        :build_id => build_id,
        :stderr_text => stderr_text,
        :message => message,
        :region => region,
        :timestamp => Time.now.gmtime.to_i
      }
      recent_errors = Redis::List.new("#{operating_mode}:#{region}:failed", redis, :max_length => MAX_NUM_RECENT_ERRORS, :marshal => true)
      recent_errors.unshift(info_hash)
      error_frequency = Redis::SortedSet.new("#{operating_mode}:#{region}:failed:#{day.strftime("%Y-%m-%d")}", redis)
      error_frequency.expire(day.to_i + REDIS_LOG_EXPIRATION)
      error_frequency.increment("#{operating_mode}:#{region}:failed")
    # Useful to keep track of successful builds/tests/monitors to get a diff once one fails
    # Definitely don't need as much context though with the one expception being the monitor state
    else
      info_hash = {
        :build_id => build_id,
        :message => message,
        :region => region,
        :timestamp => Time.now.gmtime.to_i
      }
      recent_successes = Redis::List.new("#{operating_mode}:#{region}:success", redis, :max_length => MAX_NUM_SUCCESSES, :marshal => true)
      recent_successes.unshift(info_hash)
    end
  end

  def enforce_valid_build(build_id)
    build = Build.first(:id => build_id)
    show_error(404, "No build exists with ID #{build_id}") unless build
    build
  end

end
