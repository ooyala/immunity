# A class which describes the error information associated with a stage of a Build.
class BuildStatus < Sequel::Model
  many_to_one :build
end