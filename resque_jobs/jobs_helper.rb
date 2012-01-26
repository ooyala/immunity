require "logger"

module JobsHelper
  def self.included(klass)
    klass.extend(ClassMethods)
  end

  module ClassMethods
    # Used to ensure that all necessary arguments are included in the background job's argument hash.
    def includes_options?(hash, *keys) (keys.map(&:to_s) - hash.keys).empty? end

    attr_accessor :logger

    def setup_logger(log_file_name)
      if log_file_name.include?("/")
        raise "The file name you pass to Logging.create_logger should be just a file name, not a full path."
      end
      log_file_path = File.join(File.dirname(__FILE__), "../log/", log_file_name)
      FileUtils.touch(log_file_path)

      self.logger = Logger.new(MultiIO.new(STDOUT, File.open(log_file_path, "a")))
      logger.formatter = proc do |severity, datetime, program_name, message|
        time = datetime.strftime "%Y-%m-%d %H:%M:%S"
        "[#{time}] #{message}\n"
      end
      logger
    end
  end
end

# Allow loggers to log to multiple streams at once -- a log file for troubleshooting in production,
# and STDOUT for easy troubleshooting in development.
# See stackoverflow.com/questions/6407141/how-can-i-have-ruby-logger-log-output-to-stdout-as-well-as-file
class MultiIO
  def initialize(*targets) @targets = targets end
  def write(*args) @targets.each { |target| target.write(*args) } end
  def close() @targets.each(&:close) end
end
