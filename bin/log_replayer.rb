#!/usr/bin/env ruby
# A daemon which reads log lines from Redis and makes HTTP requests based on those log lines.
# Control this daemon by sending HTTP requests to its port. The default port is 4570; set the PORT env var
# to change that.
# URLs:
#   GET /status - shows whether this log replayer is currently replaying log lines, and where to.
#   POST /status - tell it to start replaying log files from a redis bucket. Params:
#     - enabled: true/false
#     - replay_host: the host to replay requests to.
#     - redis_queue: the key of the redis queue where the log lines are stored in.
#
# To run and test this locally:
#   bundle exec bin/log_replayer.rb
#   curl localhost:4570/status
#   curl -X POST 'localhost:4570/status?enabled=true&redis_queue=abc&replay_host=localhost:8040

require "bundler/setup"
require "redis"
require "pathological"
require "script/script_environment"
require "sinatra/base"
require "sinatra/reloader"
require "thin"
require "config/environment"
require "eventmachine"
require "em-http-request"

class LogReplayer
  attr_accessor :redis_queue, :replay_host, :enabled

  def initialize(replay_host, redis_queue, redis)
    @redis = redis
    @redis_queue = redis_queue
    @replay_host = replay_host
    @enabled = true
    dequeue_from_redis
  end

  def stop() @enabled = false end

  def dequeue_from_redis
    # The Redis command "blpop" is for "blocking pop". It will keep the connection open to Redis for N
    # seconds waiting for new items to be pushed to the queue. We're explicitly backgrounding this operation
    # since it blocks. We could instead use em-synchrony's Redis wrapper which is nonblocking.
    wait_for_redis = proc do
      redis_result = @redis.blpop(@redis_queue, timeout = 5)
      next if redis_result.nil?
      # redis_result will be an array of the form [queue_name, value from queue]
      path = LogReplayer.parse_common_log_line(redis_result[1])
      unless path
        puts "Warning: could not parse the log line #{redis_result}."
        next
      end
      make_request("http://#{@replay_host}#{path}")
    end
    on_complete = proc do
      next unless @enabled
      dequeue_from_redis
    end

    EventMachine.defer(wait_for_redis, on_complete)
  end

  def make_request(url)
    puts "Requesting #{url}"
    http = EventMachine::HttpRequest.new(url).get
    http.errback { puts "Error in HTTP request to #{url}." }
    http.callback { puts "  Repsonse from #{url} of #{http.response.size} bytes." }
  rescue StandardError => error
    puts "Error when dequeueing from redis. #{error.message}\n#{error.backtrace.join("\n")}"
  end

  # Parses a Rack::CommonLogger log line and returns the URL that was accessed, or nil if it was malformed.
  def self.parse_common_log_line(log_line)
    # Log lines from Rack::CommonLogger currently look like this:
    #   127.0.0.1 - - [31/Jan/2012 16:35:37] "GET /?name=value HTTP/1.1" 200 10 0.0050
    # TODO(philc): one day we may pull out additional information (like request headers) and replay those.
    # TODO(philc): This currently only includes GET requests.
    @common_logger_regexp ||= /GET ([^ ]+) HTTP/
    match = @common_logger_regexp.match(log_line)
    match ? match[1] : nil
  end
end

class LogReplayerServer < Sinatra::Base
  @@replayer = nil

  settings.port = ENV["PORT"] || 4570
  settings.server = "thin"

  set :dump_errors, true

  get "/" do
    "log_replayer is here."
  end

  # Information about what this log replayer is currently doing.
  get "/status" do
    content_type "text/plain"
    response = []
    response << "Replaying: " + (@@replayer ? "Yes" : "No")
    if @@replayer
      response << "From Redis queue: #{@@replayer.redis_queue}"
      response << "Against host: #{@@replayer.replay_host}"
    end
    response.join("\n")
  end

  # Use this route to control the activity of the log replayer.
  post "/status" do
    ensure_params(:enabled)
    halt(400, ":enabled param is required.") unless params[:enabled]
    if params[:enabled] == "true"
      ensure_params(:replay_host, :redis_queue)
      begin_replaying(params[:replay_host], params[:redis_queue])
    else
      stop_replaying
    end
    nil
  end

  private

  def ensure_params(*required)
    required.each { |param| halt(400, "#{param} param is required.") unless params[param] }
  end

  def stop_replaying
    @@replayer.stop if @@replayer
    @@replayer = nil
  end

  def begin_replaying(replay_host, redis_queue)
    begin
      redis = connect_to_redis
    rescue => error
      halt(500, error.message)
    end

    stop_replaying
    @@replayer = LogReplayer.new(replay_host, redis_queue, redis)
  end

  def connect_to_redis
    redis = Redis.new(:host => REDIS_HOST, :port => REDIS_PORT.to_i)
    redis.ping
    redis
  end

  run! if File.basename(app_file) == File.basename($0)
end

