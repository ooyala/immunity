require "bundler/setup"
require "lib/ruby_extensions"
require "config/environment"
require "lib/models"
require "backtrace_shortener"
require "config/immunity_apps"

# Make the developer experience better by shortening stacktraces.
BacktraceShortener.monkey_patch_the_exception_class!

# Read config/immunity_apps.rb and set up corresponding database records.
IMMUNITY_APPS.each do |app_name, properties_hash|
  Application.create_application_from_hash(app_name, properties_hash)
end