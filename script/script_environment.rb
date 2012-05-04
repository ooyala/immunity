require "bundler/setup"
require "lib/ruby_extensions"
require "config/environment"
require "lib/models"
require "backtrace_shortener"
require "config/immunity_apps"
require "lib/immunity_app_config_parser"

# Make the developer experience better by shortening stacktraces.
BacktraceShortener.monkey_patch_the_exception_class!

# Read config/immunity_apps.rb and set up corresponding database records.
ImmunityAppConfigParser.parse(IMMUNITY_APPS)