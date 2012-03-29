require "bundler/setup"
require "lib/ruby_extensions"
require "config/environment"
require "lib/models"
require "backtrace_shortener"

# Make the developer experience better by shortening stacktraces.
BacktraceShortener.monkey_patch_the_exception_class!
