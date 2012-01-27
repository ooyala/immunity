#!/usr/bin/env ruby
require "bundler/setup"
require "pathological"
require "script/script_environment"
require "sinatra"

class ImmunitySystem < Sinatra::Base
  set :public_folder, "public"

  get "/" do
    "hello world"
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
