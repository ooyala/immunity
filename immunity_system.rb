#!/usr/bin/env ruby
require "bundler/setup"
require "pathological"
require "script/script_environment"
require "sinatra/base"
require "sinatra/reloader"
require "sass"
require "bourbon"
require "lib/sinatra_api_helpers"
require "redis_log_reader"
require "config/environment"

class ImmunitySystem < Sinatra::Base
  include SinatraApiHelpers

  set :public_folder, "public"
  set :show_exceptions, false

  error(500) do
    content_type "text/plain"
    env["sinatra.error"] ? env["sinatra.error"].detailed_to_s : response.body
  end

  configure :development do
    error(400) do
      # Printing the response body for 400's is useful for debugging in development.
      puts response.body
    end
    register Sinatra::Reloader
    also_reload "lib/*.rb"
    also_reload "config/*.rb"
    also_reload "resque_jobs/*.rb"
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

  get "/errors_dashboard/:product_id" do
    reader = RedisLogReader.new(REDIS_HOST, REDIS_PORT)
    errors = reader.recent_errors('html5player')
    erb :errors_dashboard, :locals => { :errors => errors }
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
    # NOTE(philc): you can set the state of a build without jumping through the state machine. Use this
    # carefully. It's useful for integration tests, but we may want to remove it if these APIs are ever
    # used by anyone else.
    if json_body[:state]
      build.state = json_body[:state]
      build.save
    else
      build.fire_events(:begin_deploy)
    end
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

    def trim_decimals(i, decimal_places)
      multiplier = 10**decimal_places
      (i * multiplier).floor / multiplier.to_f
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

  def save_build_status(build_id, stdout_text, stderr_text, message, region)
    build_status = BuildStatus.create(:build_id => build_id)
    build_status.stdout = stdout_text
    build_status.stderr = stderr_text
    build_status.message = "#{build_status.message}\n#{message}"
    build_status.region = region
    build_status.save
  end

  def enforce_valid_build(build_id)
    build = Build.first(:id => build_id)
    show_error(404, "No build exists with ID #{build_id}") unless build
    build
  end

end
