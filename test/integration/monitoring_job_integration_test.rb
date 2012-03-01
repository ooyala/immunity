require "bundler/setup"
require "pathological"
require "test/integration_test_helper"

class MonitoringJobIntegrationTest < Scope::TestCase
  include RemoteHttpTesting
  include BuildRequestHelpers

  IMMUNITY_SERVER = "http://localhost:3102"
  RESQUE_SERVER = "http://localhost:3103"

  def server() IMMUNITY_SERVER end

  setup_once do
    ensure_reachable!(server)
    ensure_reachable!(RESQUE_SERVER)
    delete "/builds/test_builds"
    use_server(RESQUE_SERVER) { delete "/queues/#{TEST_QUEUE}/jobs" }
    assert_status 200
  end

  context "monitoring" do
    setup_once do
      @@region = "integration_test_sandbox2"
      @@job_args = { :region => @@region, :monitoring_period_duration => 0 }
    end

    should "report success when latency is below our upper bound" do
      build_id = create_build(:current_region => @@region, :state => "monitoring")["id"]
      job_args = @@job_args.merge(:latency_upper_bound => 1000)

      use_server(RESQUE_SERVER) do
        post "/queues/#{TEST_QUEUE}/jobs", {}, { :class => "RunMonitor", :arguments => [job_args] }.to_json
        assert_status 200

        get "/queues/#{TEST_QUEUE}/result_of_oldest_job"
        assert_status 200
      end

      assert_equal "awaiting_confirmation", get_build(build_id)["state"]
    end

    should "report failure when laatency is above our upper bound" do
      build_id = create_build(:current_region => @@region, :state => "monitoring")["id"]
      job_args = @@job_args.merge(:latency_upper_bound => -1)

      use_server(RESQUE_SERVER) do
        post "/queues/#{TEST_QUEUE}/jobs", {}, { :class => "RunMonitor", :arguments => [job_args] }.to_json
        assert_status 200

        get "/queues/#{TEST_QUEUE}/result_of_oldest_job"
        assert_status 200
      end

      assert_equal "monitoring_failed", get_build(build_id)["state"]
    end
  end

  teardown_once do
    delete "/builds/test_builds"
  end
end
