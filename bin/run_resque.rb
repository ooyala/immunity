#!/usr/bin/env ruby

queues = %W(deploy_builds fetch_commits monitoring run_tests)

# Note that you can use * to run jobs for all queues. We're whitelisting the queues we want workers for,
# because we do not want to process jobs for temporary testing queues created by our integration tests.
# TODO(philc): In the future spin up one worker per queue.
ENV["QUEUE"] = queues.join(",")
puts "Starting Resque for queues: #{queues.join(", ")}"
exec "http_resque -p 3103", *ARGV
