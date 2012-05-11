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
    assert_status 200
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

end
