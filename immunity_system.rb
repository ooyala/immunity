#!/usr/bin/env ruby
require "bundler/setup"
require "pathological"
require "config/environment"
require "sinatra"
require "pathological"
require "lib/models"

class ImmunitySystem < Sinatra::Base
  get "/" do
    "hello world"
  end
end
