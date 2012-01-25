# A temporary script for playing with the various states of a Build. Delete this once we begin writing tests.
require "pathological"
require "script/script_environment"
require "immunity_system"

puts "\n\n"

build = Build.new
events = [:begin_deploy, :deploy_succeeded, :begin_testing, :testing_succeeded, :monitoring_succeeded]
events = events * 2

events.each do |event|
  puts "\ndispatching #{event}"
  build.fire_events(event)
  puts "state: #{build.state} region: #{build.current_region}"
end
