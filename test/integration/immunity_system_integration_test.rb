require "bundler/setup"
require "pathological"
require "test/integration_test_helper"

class ImmunitySystemIntegrationTest < Scope::TestCase
  include RemoteHttpTesting

  # This is the server all HTTP requests will be made to.
  def server() "http://localhost:3102" end

  setup_once do
    ensure_reachable!(server)
  end

  should "create and delete a build" do
    post "/builds", {},
        { :current_region => "sandbox1", :commit => "test_commit", :repo => "test_repo" }.to_json
    assert_status 200
    build_id = json_response["id"]
    delete "/builds/#{build_id}"
    assert_status 200
    get "/builds/#{build_id}"
    assert_status 404
  end

  should "return a 200 for /" do
    get "/"
    assert_status 200
  end
end