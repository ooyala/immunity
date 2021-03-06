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
    regions = Region.all
    erb :"index.html", :locals => { :regions => regions }
  end

  # Returns 200 if this server is able to service requests and 500 otherwise.
  get "/healthz" do
    begin
      DB.fetch("SELECT 1 FROM DUAL").first
    rescue => error
      halt(500, "MySQL is not reachable: #{error.message}")
    end

    begin
      @redis ||= Redis.new(:host => REDIS_HOST, :port => REDIS_PORT)
      @redis.ping
    rescue => error
      halt(500, "Redis is not reachable: #{error.message}")
    end

    "Healthy."
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

  # Create a new application and its regions. Used by our integration tests.
  # - regions: a list of regions for this app.
  # - is_test: true if this is a test build for integration testing purposes.
  #
  # An example request body:
  # { regions: [{ name: "prod1", host: "prod1.example.com" }] }
  put "/applications/:name" do
    enforce_required_json_keys(:regions)
    Application.create_application_from_hash(params[:name], json_body)
    nil
  end

  delete "/applications/:name" do
    halt 404 unless app = Application.first(:name => params[:name])
    app.destroy
    nil
  end

  # Create a new Build. Used by our integration tests.
  # - commit
  # - current_region
  post "/applications/:app_name/builds" do
    enforce_required_json_keys(:current_region, :commit)
    application = enforce_valid_app(params[:app_name])
    region = application.region_with_name(json_body[:current_region])
    halt 400, "Region #{json_body[:current_region]} doesn't exist." unless region
    build = Build.create(:current_region_id => region.id, :commit => json_body[:commit])
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

  # Used for integration tests to inspect the latest build for an app.
  get "/applications/:app_name/latest_build" do
    application = enforce_valid_app(params[:app_name])
    latest_build = application.builds_dataset.order(:builds__id.desc).first
    halt 404 unless latest_build
    latest_build.to_json
  end

  before "/builds/:id/?*" do
    @build = enforce_valid_build(params[:id])
  end

  get "/builds/:id" do
    {
      id: @build.id,
      current_region: @build.current_region.name,
      state: @build.state,
    }.to_json
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
    build_status = create_build_status(@build, "deploy", json_body)
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
    build_status = create_build_status(@build, "testing", json_body)

    if json_body[:status] == "success"
      @build.fire_events(:testing_succeeded)
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
    build_status = create_build_status(@build, "monitoring", json_body)

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
  def create_build_status(build, stage, json_body)
    status = json_body[:status]
    show_error(400, "Invalid status.") unless ["success", "failed"].include?(status)
    message = (status == "success") ? "#{stage} succeeded" : "#{stage} failed."
    region = build.application.region_with_name(json_body[:region])
    show_error(400, "Region #{json_body[:region]} doesn't exist for this app.") unless region
    BuildStatus.create(:build_id => @build.id, :message => message, :stdout => json_body[:log],
        :region_id => region.id)
  end

  def enforce_valid_app(app_name)
    application = Application.first(:name => app_name)
    show_error(404, "No application exists with name #{app_name}") unless application
    application
  end

  def enforce_valid_build(build_id)
    build = Build.first(:id => build_id)
    show_error(404, "No build exists with ID #{build_id}") unless build
    build
  end

end
