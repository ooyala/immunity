require "bundler/setup"
require "pathological"
require "test/integration_test_helper"

class ImmunitySystemIntegrationTest < Scope::TestCase
  include RemoteHttpTesting
  include BuildRequestHelpers

  def server() "http://localhost:3102" end

  setup_once do
    ensure_reachable!(server)
  end

  should "return a 200 for /" do
    get "/"
    assert_status 200
  end

  should "create an application configuration" do
    app_name = "testing"
    delete "/applications/#{app_name}"

    app_config = {
      :regions => [{ :name => "howdy", :host => "localhost", :requires_manual_approval => true }]
    }
    put "/applications/#{app_name}", {}, app_config.to_json
    assert_status 200

    build = create_build(app_name, :current_region => "howdy")
    delete "/builds/#{build['id']}"
    assert_status 200

    delete "/applications/#{app_name}"
    assert_status 200
  end

  # Take a simple, real webapp through the critical phases of the Immunity workflow.
  # The "immunity_integration_test_app" is checked out as a submodule into test/fixtures.
  context "with a real, working web app" do
    setup_once do
      @@sample_app = "immunity_integration_test_app"
      @@sample_app_url = "http://localhost:3105"
      sample_app_repo = File.expand_path(File.join(File.dirname(__FILE__), "../fixtures/#{@@sample_app}"))

      delete "/applications/#{@@sample_app}"
      delete_repo(@@sample_app)
      `cd #{REPOS_ROOT} && git clone #{sample_app_repo}`
      assert_equal 0, $?.to_i, "The command `git clone #{sample_app_repo} failed.`"

      create_application(
        :name => @@sample_app,
        :is_test => true,
        :deploy_command => "bundle exec rake deploy",
        :regions => [{ :name => "first", :host => "localhost" }])
    end

    teardown_once do
      delete "/applications/#{@@sample_app}"
      delete_repo(@@sample_app)
    end

    should "pull new commits from git" do
      get "/applications/#{@@sample_app}/latest_build"
      assert_status 404

      # Schedule a fetch_commits job in Resque.
      use_server(RESQUE_SERVER) do
        delete "/queues/#{TEST_QUEUE}/jobs"
        job_args = { :repos => [@@sample_app] }
        post "/queues/#{TEST_QUEUE}/jobs", {}, { :class => "FetchCommits", :arguments => [job_args] }.to_json
        assert_status 200
        get "/queues/#{TEST_QUEUE}/result_of_oldest_job"
        assert_status 200
      end

      latest_commit = `cd #{repo_path(@@sample_app)} && git rev-list --max-count=1 HEAD`.strip

      # Ensure that the latest Build is now in the database.
      get "/applications/#{@@sample_app}/latest_build"
      assert_status 200
      assert_equal latest_commit, json_response["commit"]
      assert_equal "deploying", json_response["state"]
    end

    context "deployment" do
      should "deploy the latest version of the app" do
        get "/applications/#{@@sample_app}/latest_build"
        assert_status 200
        assert_equal "deploying", json_response["state"]
        build_id = json_response["id"]

        use_server(RESQUE_SERVER) do
          delete "/queues/#{TEST_QUEUE}/jobs"
          job_args = { :build_id => build_id }
          post "/queues/#{TEST_QUEUE}/jobs", {}, { :class => "DeployBuild", :arguments => [job_args] }.to_json
          assert_status 200
          get "/queues/#{TEST_QUEUE}/result_of_oldest_job"
          assert_status 200
        end

        get "/applications/#{@@sample_app}/latest_build"
        assert_equal "testing", json_response["state"]
        # Our test app should be deployed and started.
        assert is_reachable?(@@sample_app_url)
      end

      teardown_once do
        # Ensure the test app is stopped.
        next
        app_path = "/tmp/#{@@sample_app}"
        if File.exists?(app_path)
          `cd #{app_path} && bundle exec rake stop`
        end
      end
    end
  end

  # TODO(philc): These tests can perhaps be folded into the context above ("with a real working webapp").
  context "with test application" do
    setup_once do
      delete "/applications/#{TEST_APP}"
      create_application(:name => TEST_APP, :is_test => true, :regions =>
          [{ :name => "sandbox1", :host => "localhost", :requires_monitoring => true,
             :requires_manual_approval => true },
           { :name => "sandbox2", :host => "localhost" }])
      @@region = "sandbox1"
    end

    teardown_once do
      delete "/applications/#{TEST_APP}"
    end

    should "prevent two builds from being deployed into the same region at the same time" do
      build1 = create_build(TEST_APP, :current_region => @@region)["id"]
      assert_equal "deploying", get_build(build1)["state"]
      build2 = create_build(TEST_APP, :current_region => @@region)["id"]
      assert_equal "awaiting_deploy", get_build(build2)["state"]
      delete_build(build1)
      delete_build(build2)
    end

    should "progress the build from deploy to testing and then to the next region" do
      build_id = create_build(TEST_APP, :current_region => @@region, :application => TEST_APP)["id"]
      assert_equal "deploying", get_build(build_id)["state"]

      # Since this app is a test_app, we will transition to the various stages, but perform no real work,
      # like doing an actual deploy.
      put "/builds/#{build_id}/deploy_status", {},
          { :status => "success", :log => "Deploy details...", :region => @@region }.to_json
      assert_status 200
      assert_equal "testing", get_build(build_id)["state"]

      put "/builds/#{build_id}/testing_status", {},
          { :status => "success", :log => "Testing details...", :region => @@region }.to_json
      assert_status 200
      assert_equal "monitoring", get_build(build_id)["state"]

      put "/builds/#{build_id}/monitoring_status", {},
          { :status => "success", :log => "Monitoring details...", :region => @@region }.to_json
      assert_status 200
      assert_equal "awaiting_confirmation", get_build(build_id)["state"]

      delete_build(build_id)
    end

  end

  def repo_path(repo_name) File.join(REPOS_ROOT, repo_name) end
  def delete_repo(repo_name)
    FileUtils.rm_rf(repo_path(repo_name)) if File.exists?(repo_path(repo_name))
  end

  def is_reachable?(host)
    exponential_backoff(5, 0.25) do
      `curl '#{host}' > /dev/null 2>&1`
      $?.to_i == 0
    end
  end

  def exponential_backoff(max_attempts, initial_sleep_time, &block)
    start = Time.now
    current_sleep_time = initial_sleep_time
    0.upto(max_attempts) do |i|
      return true if block.call
      return false if i >= (max_attempts - 1)
      sleep current_sleep_time
      current_sleep_time *= 2
    end
  end

end
