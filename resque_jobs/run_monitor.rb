# A resque job which polls for builds which have been in "monitoring" for > N minutes and inspects their
# application metrics to determine if they are good builds.

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
  SERVER_TOTAL_LATENCY_KEY = "sandbox1_latency"
  SERVER_REQUEST_COUNT = "sandbox1_request_count"

  HOST = "http://localhost:3102"

  LATENCY_UPPER_BOUND = 1000

  # The arguments hash is used by our integration tests to test each main logic path.
  # - monitoring_period_duration: how long after log replay began before we check on the app metrics.
  # - latency_upper_bound: in milliseconds.
  def self.perform(arguments = {})
    setup_logger("run_monitor.log")

    monitoring_period = Time.now -
        (arguments["monitoring_period_duration"] || Build::MONITORING_PERIOD_DURATION)
    build_dataset = Build.filter(:state => "monitoring").filter("updated_at <= ?", monitoring_period)
    build = build_dataset.first
    @logger.warn "Running monitor on #{build}"
    return unless build

    latency_upper_bound = arguments["latency_upper_bound"] || LATENCY_UPPER_BOUND

    # TODO(philc): This is just a toy comparison which needs to be reimplemented.
    begin
      redis = Redis.new :host => REDIS_SERVER, :port => REDIS_PORT
      stats = build.monitoring_stats

      if stats[:average_latency] > latency_upper_bound
        message = "Monitoring failed. Latency is #{stats[:average]}."
        @logger.info message
        RestClient.put "#{HOST}/builds/#{build.id}/monitoring_status",
            { :status => "failed", :log => message, :region => build.current_region.name }.to_json
      else
        message = "Monitoring succeeded."
        @logger.info message
        RestClient.put "#{HOST}/builds/#{build.id}/monitoring_status",
            { :status => "success", :log => message, :region => build.current_region.name }.to_json
      end
    rescue Exception => error
      message = error.detailed_to_s
      @logger.info "Monitor failed with error #{message}."
      RestClient.put "#{HOST}/builds/#{build.id}/monitoring_status",
          { :status => "failed", :log => message, :region => build.current_region.name }.to_json
    end
  end

end

if $0 == __FILE__
  RunMonitor.perform()
end
