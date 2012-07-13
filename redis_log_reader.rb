require "rubygems"
require "redis"
require "redis/objects"
require "redis/list"

class RedisLogReader

  def initialize(host, port)
    @redis = Redis.new(:host => host, :port => port)
  end

  def recent_errors(operating_mode, offset = 0, limit = 10)
    errors = Redis::List.new("#{operating_mode}:errors", @redis, :marshal => true)
    errors.range(offset, offset + limit -1)
  end

  def recent_success(operating_mode, region, offset = 0, limit = 5)
    successes = Redis::List.new("#{operating_mode}:#{region}:success", @redis, :marshal => true)
    successes.range(offset, offset + limit -1)
  end

  def get_monitor_metrics(operating_mode, region)
    today = Time.now.gmtime
    max_entry_in_redis = Time.now.gmtime - REDIS_LOG_MAX_TTL
    aggregated_results = {}
    while (today > max_entry_in_redis)
      metrics_per_day = Redis::HashKey.new("#{operating_mode}:#{region}:latency:#{today.strftime("%Y-%m-%d")}", @redis)
      metrics_keys = metrics_per_day.keys.sort
      metrics_keys.each do |build_date_key|
        aggregated_results[build_date_key] = metrics_per_day.fetch(build_date_key)
      end
      today -= 60*60*24
    end
    aggregated_results
  end

end
