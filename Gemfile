source :rubygems

gem "rake"
gem "sinatra"
gem "sass"
gem "pathological"
gem "state_machine"
gem "sequel"
gem "mysql" # For Sequel's MySQL adapter.
gem "clockwork" # For scheduling periodic jobs.
gem "foreman" # For running our 3 daemons (web service, resque, and clockwork) easily.
gem "thin" # For running the webserver in development. Production uses Unicorn.
gem "resque" # For running background jobs.
gem "open4"
gem "rest-client" # For making HTTP REST calls.
gem "redis"
gem "bourbon" # Extra CSS mixins for Sass.
gem "simple_memoize"
gem "redis-objects"
gem "sinatra-contrib" # For Sinatra::Reloader
gem "fezzik" # For deploying.
gem "http_resque" # For integration testing our Resque jobs.
gem "terraform" # For provisioning a system.
gem "backtrace_shortener" # For making exception backtraces more friendly during development.

# For the log replayer.
gem "eventmachine"
gem "em-http-request"

group :dev do
  gem "wirble" # colorized irb script/console
  gem "rerun"
  gem "vagrant", ">= 1.0.1"
  gem "watchr" # for auto-running tests when files change.
end

group :test do
  # Note that in prod we currently can't contact this test server for some reason. Even though we don't
  # deploy with "--without test", bundle install will still fail if it can't contact this gem server.
  # See https://github.com/carlhuda/bundler/issues/1745.
  # source "http://gems.us-east-1.ooyala.com:8080"
  # gem "gamut"
  gem "scope"
  gem "remote_http_testing"
  gem "rr" # for mocking & stubbign during unit testing.
end
