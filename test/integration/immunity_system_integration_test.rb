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

  should "return a 200 for /" do
    get "/"
    assert_status 200
  end
end