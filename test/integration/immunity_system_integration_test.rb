require "bundler/setup"
require "pathological"
require "test/integration_test_helper"

class ImmunitySystemIntegrationTest < Scope::TestCase
  include RemoteHttpTesting
  include BuildRequestHelpers

  # This is the server all HTTP requests will be made to.
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

    # TODO(philc): We need to set a repo name, and prevent it from scheduling a deploy.
    app_config = { :regions => [{ :name => "howdy", :host => "localhost" }] }
    put "/applications/#{app_name}", {}, app_config.to_json
    assert_status 200

    build = create_build(app_name, :current_region => "howdy")
    delete "/builds/#{build['id']}"
    assert_status 200

    delete "/applications/#{app_name}"
    assert_status 200
  end

  context "with a sample app" do
    setup_once do
      @@sample_app = "immunity_integration_test_app"
      sample_app_repo = File.expand_path(File.join(File.dirname(__FILE__), "../fixtures/#{@@sample_app}"))

      delete "/applications/#{@@sample_app}"
      delete_repo(@@sample_app)
      `cd #{REPOS_ROOT} && git clone #{sample_app_repo}`
      assert_equal 0, $?.to_i, "The command `git clone #{sample_app_repo} failed.`"
      create_application(:name => @@sample_app, :regions => [{ :name => "first", :host => "localhost" }])
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
    end
  end

  # TODO(philc): These tests can be folded into the context above.
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


end
