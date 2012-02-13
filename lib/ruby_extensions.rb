class Exception
  # A fuller representation of the exception's string representation, suitable for logging. We tend to log a
  # lot of exceptions in the immunity system.
  def detailed_to_s
    "#{self.class}: #{to_s}\n#{backtrace.join("\n")}"
  end
end