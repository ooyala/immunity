require "simple_memoize"

# This represents an application that Immunity is managing.
class Application < Sequel::Model
  one_to_many :regions
end