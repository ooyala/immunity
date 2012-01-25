require File.expand_path(File.join(File.dirname(__FILE__), "immunity_system"))
require File.expand_path(File.join(File.dirname(__FILE__), "config/environment"))
require "resque/server"

Resque.redis = "#{REDIS_HOST}:#{REDIS_PORT}"

# This URLMap setup allows us to have a resque dashboard located at "/resque".
run Rack::URLMap.new(
    "/"       => ImmunitySystem.new,
    "/resque" => Resque::Server.new)
