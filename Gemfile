source :rubygems
source "file:///opt/ooyala/sas/current/vendor/"
source "http://gems.sv2/"

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

group :dev do
  gem "wirble" # colorized irb script/console
  gem "rerun"
end

group :test do
  source "http://gems.us-east-1.ooyala.com:8080"
  gem "gamut"
  gem "scope"
  gem "mocha"
  gem "rack-test"
  gem "nokogiri"
  gem "junit_xml_builder"
end
