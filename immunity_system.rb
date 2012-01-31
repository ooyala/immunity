#!/usr/bin/env ruby
require "bundler/setup"
require "pathological"
require "script/script_environment"
require "sinatra"
require "sass"

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

  get '/index.html' do
    redirect '/'
  end

  get '/build_status/:build_id/:region' do
    build_status = BuildStatus.first(:build_id => params[:build_id], :region => params[:region])
    erb :"build_status.html", :locals => { :build_status => build_status, :region_name => params[:region] }
  end

  post "/deploy_succeed" do
    build = Build.first(:id => params[:build_id])
    build.fire_events(:deploy_succeeded)
    save_build_status(build.id, params[:stdout], params[:stderr], params[:message], params[:region])
    # trigger testting
    build.fire_events(:begin_testing)
    'ok'
  end

  post "/deploy_failed" do
    build = Build.first(:id => params[:build_id])
    build.fire_events(:deploy_failed)
    save_build_status(build.id, params[:stdout], params[:stderr], params[:message], params[:region])
    'ok'
  end

  post "/test_succeed" do
    build = Build.first(:id => params[:build_id])
    build.fire_events(:testing_succeeded)
    save_build_status(build.id, params[:stdout], params[:stderr], params[:message], params[:region])
    # trigger deploy if no monitoring required.
    if build.can_begin_deploy?
      build.fire_events(:begin_deploy)
    end
    'ok'
  end

  post "/test_failed" do
    build = Build.first(:id => params[:build_id])
    #build.fire_events(:testing_failed)
    #save_build_status(build.id, params[:stdout], params[:stderr], params[:message], params[:region])
    'ok'
  end

  # Display helpers.
  helpers do
    # Takes in a state name like "deploy_failed" and translates to "Deploy failed".
    def format_name(state)
      state.gsub("_", " ").capitalize
    end

    # Produces a time in the form of "Fri 8:23pm 30s"
    def format_time(time)
      time.strftime("%a %l:%M%P %Ss")
    end
  end

  def save_build_status(build_id, stdout_text, stderr_text, message, region)
    build_status = BuildStatus.first(:build_id => build_id, :region => region)
    if build_status.nil?
      build_status = BuildStatus.create(:build_id => build_id)
    end
    build_status.stdout = stdout_text
    build_status.stderr = stderr_text
    build_status.message = "#{build_status.message}\n#{message}"
    build_status.region = region
    build_status.save
  end

end
