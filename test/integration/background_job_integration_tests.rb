require "bundler/setup"
require "pathological"
require "test/integration_test_helper"

class MonitoringJobIntegrationTest < Scope::TestCase
  include RemoteHttpTesting
  include BuildRequestHelpers

  IMMUNITY_SERVER = "http://localhost:3102"

  def server() IMMUNITY_SERVER end

  setup_once do
    ensure_reachable!(server)
    ensure_reachable!(RESQUE_SERVER)

    delete "/applications/#{TEST_APP}"
    create_application(:name => TEST_APP, :is_test => true, :regions =>
        [{ :name => "sandbox1", :host => "localhost", :requires_monitoring => true,
           :requires_manual_approval => true },
         { :name => "sandbox2", :host => "localhost" }])

    use_server(RESQUE_SERVER) { delete "/queues/#{TEST_QUEUE}/jobs" }
    assert_status 200
  end

  context "monitoring" do
    setup_once do
      @@region = "sandbox1"
      @@job_args = { :region => @@region, :monitoring_period_duration => 0 }
    end

    should "report success when latency is below our upper bound" do
      build_id = create_build(TEST_APP, :current_region => @@region, :state => "monitoring")["id"]

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
      build_id = create_build(TEST_APP, :current_region => @@region, :state => "monitoring")["id"]
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

  context "fetch commits" do
    should "successfully access git" do
      # TODO(philc): Do not skip this test. Have this pull from a test repo on the file system, not from
      # a real, remote git server.
      skip

      use_server(RESQUE_SERVER) do
        job_args = { :repos => ["html5player"] }
        post "/queues/#{TEST_QUEUE}/jobs", {}, { :class => "FetchCommits", :arguments => [job_args] }.to_json
        assert_status 200

        get "/queues/#{TEST_QUEUE}/result_of_oldest_job"
        assert_status 200
      end
    end
  end

  teardown_once do
    delete "/applications/#{TEST_APP}"
  end
end
