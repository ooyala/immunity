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
    buiild_status = DB[:build_status]
  end

  post "/deploy_failed" do
    build = Build.first(:id => params[:build_id])
    build.fire_events(:deploy_failed)
  end

end
