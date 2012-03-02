#!/usr/bin/env ruby

# This wraps the Resque process with a thin HTTP API which enables you to manipulate jobs using HTTP requests
# and run jobs synchronously, off-box, for the purposes of integration testing background jobs. This is
# necessary because background jobs fail notoriously often in production and so they need integration -- not
# unit -- tests. This helps you to cleanly write those integration tests.
#
# You can run this HTTP server the same way you would run rake resque:work:
# QUEUE=* ./http_resque.rb -p 8080
# The server uses port 4567 by default. You can change that and other settings by using Thin's CLI arguments.

# Once it's started, you can access these URLs to manipulate jobs:
#   GET    /queues/:queue/jobs
#   DELETE /queues/:queue/jobs
#   POST   /queues/:queue/jobs
#   GET    /queues/:queue/result_of_oldest_job
#
# TODO(philc): This belongs in a gem.

require "sinatra"
require "thin"
require "resque"
require "rake"
require "json"

settings.server = "thin"

# Load the Rakefile which should in turn require all of their Resque job classes.
# TODO(philc): The path to this Rakefile should be an argument.
load "./Rakefile"

STDOUT.sync = true
STDERR.sync = true

# Run rake resque:work in a background process. It will exit when this process exits.
pid = fork { Rake::Task["resque:work"].invoke }

get "/" do
  "http_resque is here."
end

# The Resque representation of up to 25 jobs in this queue, *oldest* first. Resque jobs look like this:
#   { "class"=>"DeployBuild", "args"=>["my_embed_code", "my_youtube_synd_id"] }
get "/queues/:queue/jobs" do
  (Resque.peek(params[:queue], 0, 25) || []).to_json
end

delete "/queues/:queue/jobs" do
  Resque.remove_queue(params[:queue])
  nil
end

# Create a new job.
# - queue: the queue to enqueue this job into.
# - arguments: optional; an array of arguments for the Resque job.
post "/queues/:queue/jobs" do
  halt(400, "Provide a valid JSON body.") unless json_body
  klass = json_body["class"]
  halt(400, "Specify a class.") unless klass
  klass = Object.const_get(klass)
  Resque.enqueue_to(params[:queue], klass, *json_body["arguments"])
  nil
end

# Executes the job at the head of this queue (the oldest job), and blocks until it's finished.
# This is useful for scripting integration tests which verify that a background job is working correctly.
get "/queues/:queue/result_of_oldest_job" do
  job = Resque::Job.reserve(params[:queue])
  halt(404, "No jobs left in #{params[:queue]}") unless job
  job.perform
  nil
end

def json_body() @json_body ||= JSON.parse(request.body.read) rescue nil end
