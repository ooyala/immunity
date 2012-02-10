class BuildStatus < Sequel::Model
  many_to_one :build
end