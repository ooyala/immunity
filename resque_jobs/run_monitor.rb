# A Resque job to run "git pull" on a given repo and add an entry for the latest commit.

require "pathological"
require "script/script_environment"
require "resque_jobs/jobs_helper"
require "resque"
require "open4"
require "fileutils"
require 'rest_client'
require "redis"

class RunMonitor
  include JobsHelper
  @queue = :monitoring
  
  # TODO (rui) hard code following for now, move to environment later.
  REDIS_SERVER = "localhost"
  REDIS_PORT = 6379
  SERVER_TOTAL_LATENCY_KEY = "sandbox2_latency"
  SERVER_REQUEST_COUNT = "sandbox2_request_count"

  def self.perform()
    # hard code region to sandbox2 for now
    region = "sandbox2"
    build = Build.first(:state => 'monitoring', :current_region => region)
    return if build.nil?
    build_id = build.id
    setup_logger("run_monitor.log")
    begin
      redis = Redis.new :host => REDIS_SERVER, :port => REDIS_PORT
      total_latency = redis.get SERVER_TOTAL_LATENCY_KEY
      request_count = redis.get SERVER_REQUEST_COUNT
      average = request_count.to_i > 0 ? total_latency.to_i / request_count.to_i : 0
      puts "Average performace is #{average}"

      if average > 5000 # 5 seconds for POC purpose, we can easily add sleep to exceed the monitor threthod.
        puts "monitor failed here"
        RestClient.post 'http://localhost:3102/monitor_failed', :build_id => build_id, :region => region,
          :stdout => '', :stderr => '', :message => "monitor fail -- #{average} #{region}"
      else
        puts "Monitor succeed"
        RestClient.post 'http://localhost:3102/monitor_succeed', :build_id => build_id, :region => region,
          :stdout => '', :stderr => '', :message => "monitor succeed (#{region})-- #{Time.now}\n"
      end
    rescue Exception => e
      puts "Monitor with error #{e.inspect}\n#{e.message}\n#{e.backtrace}"
      RestClient.post 'http://localhost:3102/monitor_failed', :build_id => build_id, :region => region,
          :stdout => "", :stderr => "#{e.message}\n#{e.backtrace}", :message => "monitor error #{region}"
    end
  end

end

if $0 == __FILE__
  RunMonitor.perform()
end
