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
  end

  post "/deploy_failed" do
  end

end
