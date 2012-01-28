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
    build = Build.first
    erb :"index.html", :locals => { :build => build }
  end

  get "/styles.css" do
    scss :styles
  end

  post "/deploy_succeed" do
    build = Build.first(:id => params[:build_id])
    build.fire_events(:deploy_succeeded)
    save_build_status(build.id, params[:message], '', '')
  end

  post "/deploy_failed" do
    build = Build.first(:id => params[:build_id])
    build.fire_events(:deploy_failed)
    save_build_status(build.id, params[:message], '', '')
  end

  def save_build_status(build_id, stdout_text, stderr_text, message)
    build_status = BuildStatus.first(:build_id => build.id)
    if build_status.nil
      build_status = BuildStatus.new(:build_id => build.id)
    end
    build_status.stdout = stdout_text
    build_status.stderr = stderr_text
    build_status.message = message
    build_status.save
  end

end
