require "bundler/setup"
require "lib/ruby_extensions"
require "config/environment"
require "lib/models"
require "lib/backtrace_cleaner"

# Make the developer experience better by shortening stacktraces.
BacktraceCleaner.monkey_patch_all_exceptions!
