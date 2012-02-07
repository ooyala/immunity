#!/usr/bin/env ruby
require "bundler/setup"
require "pathological"
require "script/script_environment"
require "sinatra"
require "sass"
require "bourbon"

class ImmunitySystem < Sinatra::Base
  set :public_folder, "public"

  get "/" do
    # TODO(philc): We will pass in a list of regions to the frontend, not just a single build.
    latest_build = Build.order(:id).last
    erb :"index.html", :locals => { :latest_build => latest_build }
  end

  get "/styles.css" do
    scss :styles
  end

  get "/index.html" do
    redirect '/'
  end

  get "/build_status/:build_id/:region" do
    build_status = BuildStatus.order(:id.desc).
        first(:build_id => params[:build_id], :region => params[:region])
    erb :"build_status.html", :locals => { :build_status => build_status, :region_name => params[:region] }
  end

  post "/deploy_succeed" do
    build = Build.first(:id => params[:build_id])
    build.fire_events(:deploy_succeeded)
    save_build_status(build.id, params[:stdout], params[:stderr], params[:message], params[:region])
    build.fire_events(:begin_testing)
    nil
  end

  post "/deploy_failed" do
    build = Build.first(:id => params[:build_id])
    save_build_status(build.id, params[:stdout], params[:stderr], params[:message], params[:region])
    build.fire_events(:deploy_failed)
    nil
  end

  post "/test_succeed" do
    build = Build.first(:id => params[:build_id])
    save_build_status(build.id, params[:stdout], params[:stderr], params[:message], params[:region])
    build.fire_events(:testing_succeeded)
    build.fire_events(:begin_deploy) if build.can_begin_deploy?
    nil
  end

  post "/test_failed" do
    build = Build.first(:id => params[:build_id])
    save_build_status(build.id, params[:stdout], params[:stderr], params[:message], params[:region])
    build.fire_events(:testing_failed)
    nil
  end

  post "/monitor_succeed" do
    build = Build.first(:id => params[:build_id])
    save_build_status(build.id, params[:stdout], params[:stderr], params[:message], params[:region])
    build.fire_events(:monitoring_succeeded)
    nil
  end

  post "/monitor_failed" do
    build = Build.first(:id => params[:build_id])
    save_build_status(build.id, params[:stdout], params[:stderr], params[:message], params[:region])
    build.fire_events(:monitoring_failed)
    nil
  end

  # Manually confirms that a build is OK and begins deploying it to prod3.
  # - build_id
  post "/manual_deploy_confirmed" do
    build = Build.first(:id => params[:build_id])
    build.fire_events(:manual_deploy_confirmed)
    build.fire_events(:begin_deploy)
    nil
  end

  # Display helpers.
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

  def save_build_status(build_id, stdout_text, stderr_text, message, region)
    build_status = BuildStatus.create(:build_id => build_id)
    build_status.stdout = stdout_text
    build_status.stderr = stderr_text
    build_status.message = "#{build_status.message}\n#{message}"
    build_status.region = region
    build_status.save
  end

end
