#!/usr/bin/env ruby
require "bundler/setup"
require "pathological"
require "script/script_environment"
require "sinatra"

class ImmunitySystem < Sinatra::Base
  get "/" do
    "hello world"
  end
end
