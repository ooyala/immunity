require "bundler/setup"
require "pathological"
require "test/unit_test_helper"
require "lib/models"
require "logger"

class BuildTest < Scope::TestCase
  prevent_live_database_access

  setup do
    @build = Build.new
    @region1 = Region.new(:id => 1, :name => "sandbox1", :host => "sandbox1.com", :requires_monitoring => true)
    @region2 = Region.new(:id => 2, :name => "sandbox2", :host => "sandbox1.com")
    application = Application.new(:name => "test app")
    stub(@build).application { application }
    stub(application).regions { [@region1, @region2] }
    stub(@build).current_region { @region1 }
    stub_saving(@build)
    @build.logger = Logger.new("/dev/null")
  end

  context "log forwarding" do
    setup do
      @build.state = "testing"
      stub(BuildStatus).create
    end

    should "make a POST request when beginning log forwarding" do
      @url, @params = nil
      stub(RestClient).post { |url, params| @url = url; @params = params }

      @build.fire_events(:testing_succeeded)
      assert_equal "monitoring", @build.state
      assert_equal "#{@region1.host}:#{LOG_FORWARDER_PORT}/status", @url
    end

    should "report failure if the log forwarder daemon is not running" do
      stub(RestClient).post { raise Errno::ECONNREFUSED.new }
      @build.fire_events(:testing_succeeded)
      assert_equal "monitoring_failed", @build.state
    end

    should "stop log forwarding when finished with monitoring" do
      @url, @params = nil
      stub(RestClient).post { |url, params| @url = url; @params = params }
      @build.state = "monitoring"
      @build.fire_events(:monitoring_failed)
      assert_equal "#{@region1.host}:#{LOG_FORWARDER_PORT}/status", @url
      assert_equal false, @params[:enabled].nil?
    end

    should "fail monitoring if we're unable to stop log forwarding" do
      stub(RestClient).post { }
      @build.state = "monitoring"
      @build.fire_events(:monitoring_succeeded)
      assert_equal "awaiting_deploy", @build.state

      @build.state = "monitoring"
      stub(RestClient).post { raise Errno::ECONNREFUSED.new }
      @build.fire_events(:monitoring_succeeded)
      assert_equal "monitoring_failed", @build.state
    end
  end
end