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
    delete "/builds/test_builds"
    assert_status 200
  end

  should "return a 200 for /" do
    get "/"
    assert_status 200
  end

  should "create and delete a build" do
    build_id = create_build["id"]

    get "/builds/#{build_id}"
    assert_status 200

    delete "/builds/#{build_id}"
    assert_status 200

    get "/builds/#{build_id}"
    assert_status 404
  end

  context "core workflow" do
    setup_once do
      @@region = "integration_test_sandbox2"
      @@build_id = create_build(:current_region => @@region)["id"]
    end

    should "progress the build from deploy to testing and then to the next region" do
      assert_equal "deploying", get_build(@@build_id)["state"]

      put "/builds/#{@@build_id}/deploy_status", {},
          { :status => "success", :log => "Deploy details...", :region => @@region }.to_json
      assert_status 200
      assert_equal "testing", get_build(@@build_id)["state"]

      put "/builds/#{@@build_id}/testing_status", {},
          { :status => "success", :log => "Testing details...", :region => @@region }.to_json
      assert_status 200
      assert_equal "monitoring", get_build(@@build_id)["state"]

      put "/builds/#{@@build_id}/monitoring_status", {},
          { :status => "success", :log => "Monitoring details...", :region => @@region }.to_json
      assert_status 200
      assert_equal "awaiting_confirmation", get_build(@@build_id)["state"]

      delete "/builds/#{@build_id}"
    end
  end

end
