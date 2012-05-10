ENV["RACK_ENV"] = "test"

require "bundler/setup"
require "script/script_environment"
require "scope"
require "minitest/autorun"
require "pathological"
require "rack/test"
require "rr"
require "nokogiri"

module Scope
  class TestCase
    include RR::Adapters::MiniTest

    def assert_status(status_code) assert_equal status_code, last_response.status end
    def dom_response
      @dom_response ||= Nokogiri::HTML(last_response.body)
    end

    # Call this at the top of your unit test class to start throwing exceptions if a live call to the
    # database is made which isn't stubbed out. This is to ensure that our unit tests don't depend on
    # live database calls, for performance and hygenic reasons.
    def self.prevent_live_database_access() @@prevent_live_database_access = true end

    # This wraps the setup() method that test case classes define and stubs out live database queries if
    # prevent_live_database_access has been called.
    # NOTE(philc): If you override setup in your test case, you must call "super" in your setup method
    # for this wrapped version to be called.
    unless method_defined?(:original_setup)
      alias_method :original_setup, :setup
      def server_test_setup
        original_setup
        if defined?(@@prevent_live_database_access) && @@prevent_live_database_access
          stub(Sequel::MySQL::Database).instance
          any_instance_of(Sequel::MySQL::Database) do |db|
            stub(db).execute do |*args|
              sql = args.first
              raise "You're making calls to the live MySQL database from a unit test. " +
                  "For performance and hygenic reasons, you should stub out those calls to the DB.\n#{sql}"
            end
          end
        end
      end
      alias_method :setup, :server_test_setup
    end

    def stub_saving(model)
      # Stubbing these private, low-level method which is actually does the DB write as part of model.save.
      # We don't want to stub "save" itself, because we want all before- and after-save callbacks to be fired.
      stub(model)._update_columns
      stub(model)._save_refresh
      stub(model)._insert { 1 }
    end
  end
end
