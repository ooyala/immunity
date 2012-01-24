require "rubygems"
require "sinatra"
require "pathological"

class ImmunitySystem < Sinatra::Base
  get "/" do
    "hello world"
  end
end
