# A Resque job to run "git pull" on a given repo and add an entry for the latest commit.

require "pathological"
require "script/script_environment"
require "resque_jobs/jobs_helper"
require "resque"
require "fileutils"
require "rest_client"
require "redis"

class RunMonitor
  include JobsHelper
  @queue = :monitoring

  # TODO (rui) hard code following for now, move to environment later.
  REDIS_SERVER = "localhost"
  REDIS_PORT = 6379
  SERVER_TOTAL_LATENCY_KEY = "sandbox2_latency"
  SERVER_REQUEST_COUNT = "sandbox2_request_count"

  HOST = "http://localhost:3102"

  def self.perform()
    setup_logger("run_monitor.log")

    monitoring_period = Time.now - Build::MONITORING_PERIOD_DURATION
    build = Build.filter(:state => "monitoring").filter("updated_at < ?", monitoring_period).first
    return if build.nil?

    region = build.region

    # TODO(philc): This is just a toy comparison which needs to be reimplemented this to be more
    # complete and informative.
    begin
      redis = Redis.new :host => REDIS_SERVER, :port => REDIS_PORT
      total_latency = redis.get SERVER_TOTAL_LATENCY_KEY
      request_count = redis.get SERVER_REQUEST_COUNT
      average = request_count.to_i > 0 ? total_latency.to_i / request_count.to_i : 0
      puts "Average performace is #{average}"

      if average > 5000 # 5 seconds for POC purpose, we can easily add sleep to exceed the monitor threshold.
        puts "Monitoring failed."
        RestClient.put "#{HOST}/builds/#{build.id}/monitoring_status",
            { :status => "failed", :log => "latency is : #{average} @ #{region}", :region => region }.to_json
      else
        puts "Monitoring succeeded."
        message = "average latency is #{average}"
        RestClient.put "#{HOST}/builds/#{build.id}/monitoring_status",
            { :status => "success", :log => message, :region => region }.to_json
      end
    rescue Exception => error
      message = error.detailed_to_s
      puts "Monitor failed with error #{message}"
      RestClient.put "#{HOST}/builds/#{build.id}/monitoring_status",
          { :status => "failed", :log => message, :region => region }.to_json
    end
  end

end

if $0 == __FILE__
  RunMonitor.perform()
end
